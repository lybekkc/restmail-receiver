use serde::Deserialize;
use std::fs;
use std::path::Path;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use chrono::Local;
use uuid::Uuid;

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

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Last konfigurasjon
    let config = load_config();
    let addr = &config.network.listen_address;

    // 2. Sett opp lyttere
    let policy_listener = TcpListener::bind(format!("{}:{}", addr, config.network.policy_port)).await?;
    let delivery_listener = TcpListener::bind(format!("{}:{}", addr, config.network.delivery_port)).await?;

    println!("🚀 Restmail System Aktivt!");
    println!("🛡️ Policy Service på port {}", config.network.policy_port);
    println!("📥 Mail Delivery på port {}", config.network.delivery_port);

    loop {
        let conf = config.clone();
        tokio::select! {
            // Håndter Policy-sjekk (Postfix dørvakt)
            Ok((socket, _)) = policy_listener.accept() => {
                tokio::spawn(async move {
                    if let Err(e) = handle_policy(socket).await {
                        eprintln!("Policy feil: {}", e);
                    }
                });
            }
            // Håndter Mail-levering (Selve e-posten)
            Ok((socket, _)) = delivery_listener.accept() => {
                tokio::spawn(async move {
                    if let Err(e) = handle_mail_delivery(socket, conf).await {
                        eprintln!("Delivery feil: {}", e);
                    }
                });
            }
        }
    }
}

fn load_config() -> Config {
    let path = "/etc/restmail-receiver/config.toml";
    let content = fs::read_to_string(path)
        .unwrap_or_else(|_| panic!("Kunne ikke lese {}", path));
    toml::from_str(&content).expect("Feil i TOML-format")
}

// --- PORT 12345: POLICY SERVICE ---
async fn handle_policy(socket: TcpStream) -> std::io::Result<()> {
    let mut reader = BufReader::new(socket);
    let mut line = String::new();
    let mut recipient = String::new();

    while reader.read_line(&mut line).await? > 0 {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            let response = if recipient.ends_with("@restmail.org") {
                "action=OK\n\n"
            } else {
                "action=REJECT Domene ikke støttet\n\n"
            };
            // Skriv via reader.get_mut()
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

// --- PORT 2525: SMTP DELIVERY ---
async fn handle_mail_delivery(mut socket: TcpStream, config: Config) -> std::io::Result<()> {
    // Vi flytter socket inn i BufReader med en gang
    let mut reader = BufReader::new(socket); 
    let mut line = String::new();
    let mut email_data = String::new();
    let mut in_data_mode = false;

    // Bruk reader.get_mut() for å skrive
    reader.get_mut().write_all(b"220 localhost ESMTP Restmail-Receiver\r\n").await?;

    loop {
        line.clear();
        if reader.read_line(&mut line).await? == 0 { break; }
        let trimmed = line.trim();

        if in_data_mode {
            if trimmed == "." {
                // Finn dette partiet inne i DATA-håndteringen i handle_mail_delivery:
if trimmed == "." {
    let id = Uuid::new_v4();
    let timestamp = Local::now().format("%Y%m%d_%H%M%S");
    let file_name = format!("{}_{}.eml", timestamp, id);

    // SLÅ SAMMEN STIER: f.eks. "/var/mail/restmail" + "incoming"
    let full_path = Path::new(&config.storage.base_path).join(&config.storage.incoming);
    let file_path = full_path.join(file_name);

    // Sørg for at hele stien eksisterer
    if let Err(e) = fs::create_dir_all(&full_path) {
        eprintln!("❌ Feil ved opprettelse av mappe {:?}: {}", full_path, e);
    }

    match tokio::fs::write(&file_path, &email_data).await {
        Ok(_) => {
            println!("📧 Mail suksessfullt lagret i: {:?}", file_path);
            reader.get_mut().write_all(b"250 2.0.0 Ok: Queued\r\n").await?;
        },
        Err(e) => {
            eprintln!("❌ Kunne ikke skrive fil til {:?}: {}", file_path, e);
            reader.get_mut().write_all(b"451 4.3.0 Error: Could not write file\r\n").await?;
        }
    }

    in_data_mode = false;
    email_data.clear();
}
            } else {
                email_data.push_str(&line);
            }
        } else {
            match trimmed.to_uppercase().as_str() {
                t if t.starts_with("HELO") || t.starts_with("EHLO") => {
                    reader.get_mut().write_all(b"250 Hello\r\n").await?;
                }
                t if t.starts_with("MAIL FROM") || t.starts_with("RCPT TO") => {
                    reader.get_mut().write_all(b"250 Ok\r\n").await?;
                }
                "DATA" => {
                    in_data_mode = true;
                    reader.get_mut().write_all(b"354 End data with <CR><LF>.<CR><LF>\r\n").await?;
                }
                "QUIT" => {
                    reader.get_mut().write_all(b"221 Bye\r\n").await?;
                    break;
                }
                _ => { 
                    reader.get_mut().write_all(b"500 Unknown\r\n").await?; 
                }
            }
        }
    }
    Ok(())
}
