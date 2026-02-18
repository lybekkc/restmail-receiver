use serde::Deserialize;
use std::fs;
use std::path::Path;
use std::env;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use chrono::Local;
use uuid::Uuid;
use tracing::{info, warn, error, debug, instrument};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};
use tracing_appender::rolling::{RollingFileAppender, Rotation};

mod api_client;
mod email_parser;

use api_client::{ApiClient, ReceiveEmailRequest};
use email_parser::ParsedEmail;

#[derive(Deserialize, Clone)]
struct Config {
    network: NetworkConfig,
    storage: StorageConfig,
}

#[derive(Deserialize, Clone)]
struct NetworkConfig {
    policy_port: u16,
    delivery_port: u16,
    listen_address: String,
}

#[derive(Deserialize, Clone)]
struct StorageConfig {
    base_path: String,
    incoming: String,
}

fn init_logger() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Detect if running in a container or Kubernetes
    let in_container = env::var("KUBERNETES_SERVICE_HOST").is_ok()
        || env::var("DOCKER_CONTAINER").is_ok()
        || Path::new("/.dockerenv").exists()
        || env::var("RESTMAIL_LOG_MODE").as_deref() == Ok("stdout");

    // Get log directory from environment or use default
    let log_dir = env::var("RESTMAIL_LOG_DIR")
        .unwrap_or_else(|_| "/var/log/restmail-receiver".to_string());

    // Check if the log directory is writable (indicates a mounted volume)
    let log_dir_writable = if in_container {
        // Try to create the directory to see if it's writable
        fs::create_dir_all(&log_dir).is_ok()
            && fs::metadata(&log_dir).map(|m| !m.permissions().readonly()).unwrap_or(false)
    } else {
        true // Assume writable on bare-metal
    };

    // Set up env filter (default to info level)
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    if in_container && !log_dir_writable {
        // Container mode without volume mount: Log only to stdout
        tracing_subscriber::registry()
            .with(env_filter)
            .with(
                tracing_subscriber::fmt::layer()
                    .with_writer(std::io::stdout)
                    .with_ansi(false)
                    .with_target(false)
            )
            .init();

        info!("Logger initialized in container mode (stdout only - no volume mounted)");
    } else {
        // Bare-metal mode OR container with mounted volume: Try to log to file + stdout
        // Try to create log directory - if it fails, fall back to stdout only
        match fs::create_dir_all(&log_dir) {
            Ok(_) => {
                // Directory created successfully, set up file + stdout logging
                let file_appender = RollingFileAppender::new(
                    Rotation::DAILY,
                    &log_dir,
                    "restmail.log"
                );

                let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

                // Set up the subscriber with both file and stdout
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(
                        tracing_subscriber::fmt::layer()
                            .with_writer(non_blocking)
                            .with_ansi(false)
                            .with_target(false)
                    )
                    .with(
                        tracing_subscriber::fmt::layer()
                            .with_writer(std::io::stdout)
                            .with_target(false)
                    )
                    .init();

                if in_container {
                    info!("Logger initialized in container mode with volume mount, writing to: {}/restmail.log", log_dir);
                } else {
                    info!("Logger initialized in bare-metal mode, writing to: {}/restmail.log", log_dir);
                }
            },
            Err(e) => {
                // Failed to create log directory - fall back to stdout only
                tracing_subscriber::registry()
                    .with(env_filter)
                    .with(
                        tracing_subscriber::fmt::layer()
                            .with_writer(std::io::stdout)
                            .with_ansi(false)
                            .with_target(false)
                    )
                    .init();

                warn!("Failed to create log directory '{}': {} - falling back to stdout-only logging", log_dir, e);
                info!("Logger initialized in stdout-only mode (log directory not writable)");
            }
        }
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Load .env file first (before logger initialization)
    let _ = dotenv::dotenv();

    // Initialize logger
    init_logger()?;

    info!("🚀 Starting Restmail Receiver");

    // Check API mode
    if is_api_mode_enabled() {
        info!("✅ API mode: ENABLED (will use REST API for validation and storage)");
        println!("✅ API mode: ENABLED");
        println!("   API URL: {}", env::var("REST_API_URL").unwrap_or_else(|_| "not set".to_string()));
    } else {
        warn!("⚠️  API mode: DISABLED (using fallback mode - accepts @restmail.org only)");
        println!("⚠️  API mode: DISABLED");
        println!("   Running in fallback mode (accepts @restmail.org, saves to file only)");
        println!("   To enable API mode, set: REST_API_SERVICE_KEY and REST_API_SECRET_KEY");
    }

    // 1. Last konfigurasjon
    let config = load_config();
    let addr = &config.network.listen_address;

    // 2. Sett opp lyttere
    let policy_listener = TcpListener::bind(format!("{}:{}", addr, config.network.policy_port)).await?;
    let delivery_listener = TcpListener::bind(format!("{}:{}", addr, config.network.delivery_port)).await?;

    info!("Policy Service listening on {}:{}", addr, config.network.policy_port);
    info!("Mail Delivery listening on {}:{}", addr, config.network.delivery_port);

    println!("🚀 Restmail System Aktivt!");
    println!("🛡️ Policy Service på port {}", config.network.policy_port);
    println!("📥 Mail Delivery på port {}", config.network.delivery_port);

    loop {
        let conf = config.clone();
        tokio::select! {
            // Håndter Policy-sjekk (Postfix dørvakt)
            Ok((socket, addr)) = policy_listener.accept() => {
                debug!("Policy connection from: {}", addr);
                tokio::spawn(async move {
                    if let Err(e) = handle_policy(socket).await {
                        error!("Policy handler error: {}", e);
                        eprintln!("Policy feil: {}", e);
                    }
                });
            }
            // Håndter Mail-levering (Selve e-posten)
            Ok((socket, addr)) = delivery_listener.accept() => {
                debug!("Mail delivery connection from: {}", addr);
                tokio::spawn(async move {
                    if let Err(e) = handle_mail_delivery(socket, conf).await {
                        error!("Mail delivery handler error: {}", e);
                        eprintln!("Delivery feil: {}", e);
                    }
                });
            }
        }
    }
}

fn load_config() -> Config {
    // Note: .env file is loaded in main() before this function is called

    // Check if environment variables are set
    let env_policy_port = env::var("RESTMAIL_POLICY_PORT").ok();
    let env_delivery_port = env::var("RESTMAIL_DELIVERY_PORT").ok();
    let env_listen_address = env::var("RESTMAIL_LISTEN_ADDRESS").ok();
    let env_base_path = env::var("RESTMAIL_STORAGE_BASE_PATH").ok();
    let env_incoming = env::var("RESTMAIL_STORAGE_INCOMING").ok();

    // If all required environment variables are set, use them
    if env_policy_port.is_some() && env_delivery_port.is_some() && env_listen_address.is_some()
        && env_base_path.is_some() && env_incoming.is_some() {

        info!("Loading configuration from environment variables");
        println!("📌 Laster konfigurasjon fra miljøvariabler");

        Config {
            network: NetworkConfig {
                policy_port: env_policy_port.unwrap().parse().expect("RESTMAIL_POLICY_PORT må være et gyldig tall"),
                delivery_port: env_delivery_port.unwrap().parse().expect("RESTMAIL_DELIVERY_PORT må være et gyldig tall"),
                listen_address: env_listen_address.unwrap(),
            },
            storage: StorageConfig {
                base_path: env_base_path.unwrap(),
                incoming: env_incoming.unwrap(),
            },
        }
    } else {
        // Fall back to config file
        let config_path = env::var("RESTMAIL_CONFIG_PATH")
            .unwrap_or_else(|_| "/etc/restmail-receiver/config.toml".to_string());

        info!("Loading configuration from file: {}", config_path);
        println!("📌 Laster konfigurasjon fra fil: {}", config_path);

        let content = fs::read_to_string(&config_path)
            .unwrap_or_else(|_| panic!("Kunne ikke lese {}", config_path));

        let mut config: Config = toml::from_str(&content).expect("Feil i TOML-format");

        // Allow environment variables to override individual config file values
        if let Ok(port) = env::var("RESTMAIL_POLICY_PORT") {
            config.network.policy_port = port.parse().expect("RESTMAIL_POLICY_PORT må være et gyldig tall");
        }
        if let Ok(port) = env::var("RESTMAIL_DELIVERY_PORT") {
            config.network.delivery_port = port.parse().expect("RESTMAIL_DELIVERY_PORT må være et gyldig tall");
        }
        if let Ok(addr) = env::var("RESTMAIL_LISTEN_ADDRESS") {
            config.network.listen_address = addr;
        }
        if let Ok(path) = env::var("RESTMAIL_STORAGE_BASE_PATH") {
            config.storage.base_path = path;
        }
        if let Ok(incoming) = env::var("RESTMAIL_STORAGE_INCOMING") {
            config.storage.incoming = incoming;
        }

        config
    }
}

// --- PORT 12345: POLICY SERVICE ---
#[instrument(skip(socket))]
async fn handle_policy(socket: TcpStream) -> std::io::Result<()> {
    let mut reader = BufReader::new(socket);
    let mut line = String::new();
    let mut recipient = String::new();

    while reader.read_line(&mut line).await? > 0 {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            // Check recipient via API
            let response = match check_recipient_policy(&recipient).await {
                Ok(true) => {
                    info!("Policy check: ACCEPTED for recipient: {}", recipient);
                    "action=OK\n\n"
                }
                Ok(false) => {
                    warn!("Policy check: REJECTED for recipient: {}", recipient);
                    "action=REJECT Email address not found\n\n"
                }
                Err(e) => {
                    error!("Policy check error for {}: {}", recipient, e);
                    // On error, reject to be safe
                    "action=DEFER_IF_PERMIT Service temporarily unavailable\n\n"
                }
            };

            reader.get_mut().write_all(response.as_bytes()).await?;
            break;
        }

        if trimmed.starts_with("recipient=") {
            recipient = trimmed.split('=').last().unwrap_or("").to_string();
        }
        line.clear();
    }
    Ok(())
}

/// Check if recipient is valid via API or fallback mode
async fn check_recipient_policy(recipient: &str) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    // Check if API mode is enabled
    if !is_api_mode_enabled() {
        // Fallback mode: Accept all @restmail.org emails
        debug!("API mode disabled, using fallback policy (accept @restmail.org)");
        return Ok(recipient.ends_with("@restmail.org"));
    }

    // Get API client
    let api_client = match get_api_client() {
        Some(client) => client,
        None => {
            warn!("API credentials not configured, falling back to simple policy");
            return Ok(recipient.ends_with("@restmail.org"));
        }
    };

    // Extract domain from email
    let domain = ParsedEmail::extract_domain(recipient)
        .ok_or("Invalid email format")?;

    // 1. Check if domain exists and is active
    match api_client.lookup_domain(&domain).await {
        Ok(domain_response) => {
            if !domain_response.exists || !domain_response.is_active {
                debug!("Domain {} not found or inactive", domain);
                return Ok(false);
            }
        }
        Err(e) => {
            error!("Domain lookup failed: {} - falling back to accept", e);
            // On API error, accept to avoid blocking legitimate mail
            return Ok(true);
        }
    }

    // 2. Check if email exists (with plus addressing support)
    match api_client.lookup_email(recipient).await {
        Ok(email_response) => {
            if email_response.exists {
                debug!("Email {} exists", recipient);
                return Ok(true);
            }
        }
        Err(e) => {
            error!("Email lookup failed: {} - falling back to accept", e);
            return Ok(true);
        }
    }

    // 3. Check if it's an alias
    match api_client.lookup_alias(recipient).await {
        Ok(alias_response) => {
            if alias_response.is_alias {
                debug!("Email {} is an alias", recipient);
                return Ok(true);
            }
        }
        Err(e) => {
            error!("Alias lookup failed: {} - falling back to accept", e);
            return Ok(true);
        }
    }

    // Email not found
    Ok(false)
}

/// Get API client from environment variables (returns None if not configured)
fn get_api_client() -> Option<ApiClient> {
    let base_url = env::var("REST_API_URL").ok()?;
    let service_key = env::var("REST_API_SERVICE_KEY").ok()?;
    let secret_key = env::var("REST_API_SECRET_KEY").ok()?;

    Some(ApiClient::new(base_url, service_key, secret_key))
}

/// Check if API mode is enabled
fn is_api_mode_enabled() -> bool {
    env::var("REST_API_SERVICE_KEY").is_ok()
        && env::var("REST_API_SECRET_KEY").is_ok()
}

/// Send email to API (returns None if API mode disabled)
async fn send_email_to_api(
    email: ParsedEmail,
    file_path: String,
) -> Option<api_client::ReceiveEmailResponse> {
    // Check if API mode is enabled
    if !is_api_mode_enabled() {
        debug!("API mode disabled, skipping API delivery");
        return None;
    }

    let api_client = get_api_client()?;

    let request = ReceiveEmailRequest {
        from: email.from.clone(),
        to: email.to.clone(),
        cc: email.cc.clone(),
        bcc: email.bcc.clone(),
        subject: email.subject.clone(),
        body_text: email.body_text.clone(),
        body_html: email.body_html.clone(),
        headers: Some(serde_json::to_value(&email.headers).ok()?),
        attachments: Vec::new(), // TODO: Parse attachments
    };

    debug!("Sending email to API: from={}, to={:?}", request.from, request.to);

    match api_client.receive_email(request).await {
        Ok(response) => Some(response),
        Err(e) => {
            error!("API delivery failed: {}", e);
            None
        }
    }
}

// --- PORT 2525: SMTP DELIVERY ---
#[instrument(skip(socket, config))]
async fn handle_mail_delivery(socket: TcpStream, config: Config) -> std::io::Result<()> {
    // Vi flytter socket inn i BufReader med en gang
    let mut reader = BufReader::new(socket); 
    let mut line = String::new();
    let mut email_data = String::new();
    let mut in_data_mode = false;
    let mut mail_from = String::new();
    let mut rcpt_to = String::new();

    // Bruk reader.get_mut() for å skrive
    reader.get_mut().write_all(b"220 localhost ESMTP Restmail-Receiver\r\n").await?;
    debug!("SMTP session started");

    loop {
        line.clear();
        if reader.read_line(&mut line).await? == 0 { break; }
        let trimmed = line.trim();

        if in_data_mode {
            if trimmed == "." {
                // Parse email data
                let parsed_email = ParsedEmail::parse_from_data(&email_data);

                // Save to file (backup/original copy)
                let id = Uuid::new_v4();
                let timestamp = Local::now().format("%Y%m%d_%H%M%S");
                let file_name = format!("{}_{}.eml", timestamp, id);
                let full_path = Path::new(&config.storage.base_path).join(&config.storage.incoming);
                let file_path = full_path.join(&file_name);

                // Ensure directory exists
                if let Err(e) = fs::create_dir_all(&full_path) {
                    error!("Failed to create directory {:?}: {}", full_path, e);
                }

                // Save original .eml file
                let file_saved = match tokio::fs::write(&file_path, &email_data).await {
                    Ok(_) => {
                        info!("Mail file saved: {:?}", file_path);
                        true
                    }
                    Err(e) => {
                        error!("Failed to write mail file {:?}: {}", file_path, e);
                        false
                    }
                };

                // Send to API for database storage
                match send_email_to_api(parsed_email, file_path.to_string_lossy().to_string()).await {
                    Some(response) => {
                        let success_count = response.delivered_to.iter().filter(|r| r.success).count();
                        let total = response.delivered_to.len();

                        info!(
                            "Email processed via API: {} ({}/{} recipients)",
                            response.message, success_count, total
                        );

                        if success_count == total {
                            println!("✅ Email delivered to {}/{} recipients via API", success_count, total);
                            reader.get_mut().write_all(b"250 2.0.0 Ok: Queued\r\n").await?;
                        } else if success_count > 0 {
                            println!("⚠️  Email partially delivered: {}/{} recipients", success_count, total);
                            reader.get_mut().write_all(b"250 2.0.0 Ok: Partially queued\r\n").await?;
                        } else {
                            error!("Email delivery failed for all recipients");
                            if file_saved {
                                reader.get_mut().write_all(b"250 2.0.0 Ok: Queued (file only)\r\n").await?;
                            } else {
                                reader.get_mut().write_all(b"550 5.1.1 Delivery failed\r\n").await?;
                            }
                        }
                    }
                    None => {
                        // API mode disabled or failed
                        if file_saved {
                            info!("Email saved to file (API mode disabled or unavailable)");
                            println!("📧 Mail saved to file: {:?}", file_path);
                            reader.get_mut().write_all(b"250 2.0.0 Ok: Queued\r\n").await?;
                        } else {
                            error!("Failed to save email");
                            reader.get_mut().write_all(b"451 4.3.0 Error: Could not save email\r\n").await?;
                        }
                    }
                }

                in_data_mode = false;
                email_data.clear();
            } else {
                email_data.push_str(&line);
            }
        } else {
            match trimmed.to_uppercase().as_str() {
                t if t.starts_with("HELO") || t.starts_with("EHLO") => {
                    debug!("SMTP command: {}", trimmed);
                    reader.get_mut().write_all(b"250 Hello\r\n").await?;
                }
                t if t.starts_with("MAIL FROM") => {
                    mail_from = trimmed.to_string();
                    debug!("SMTP command: {}", trimmed);
                    reader.get_mut().write_all(b"250 Ok\r\n").await?;
                }
                t if t.starts_with("RCPT TO") => {
                    rcpt_to = trimmed.to_string();
                    debug!("SMTP command: {}", trimmed);
                    reader.get_mut().write_all(b"250 Ok\r\n").await?;
                }
                "DATA" => {
                    info!("Starting mail delivery: from={}, to={}", mail_from, rcpt_to);
                    in_data_mode = true;
                    reader.get_mut().write_all(b"354 End data with <CR><LF>.<CR><LF>\r\n").await?;
                }
                "QUIT" => {
                    debug!("SMTP session ended");
                    reader.get_mut().write_all(b"221 Bye\r\n").await?;
                    break;
                }
                _ => { 
                    warn!("Unknown SMTP command: {}", trimmed);
                    reader.get_mut().write_all(b"500 Unknown\r\n").await?;
                }
            }
        }
    }
    Ok(())
}
