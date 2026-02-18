// API Client for communicating with the REST API
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use hmac::{Hmac, Mac};
use sha2::{Sha256, Digest};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone)]
pub struct ApiClient {
    base_url: String,
    service_key: String,
    secret_key: String,
    client: reqwest::Client,
}

// Request/Response structures
#[derive(Serialize)]
pub struct DomainLookupRequest {
    pub domain: String,
}

#[derive(Deserialize, Debug)]
pub struct DomainLookupResponse {
    pub exists: bool,
    pub is_active: bool,
    pub is_public: bool,
    pub domain_id: Option<Uuid>,
}

#[derive(Serialize)]
pub struct EmailLookupRequest {
    pub email: String,
}

#[derive(Deserialize, Debug)]
pub struct EmailLookupResponse {
    pub exists: bool,
    pub normalized_email: Option<String>,
    pub user_id: Option<Uuid>,
    pub email_address_id: Option<Uuid>,
    pub is_primary: Option<bool>,
    pub matched_via_plus_addressing: Option<bool>,
}

#[derive(Serialize)]
pub struct AliasLookupRequest {
    pub email: String,
}

#[derive(Deserialize, Debug)]
pub struct AliasLookupResponse {
    pub is_alias: bool,
    pub normalized_alias: Option<String>,
    pub alias_id: Option<Uuid>,
    pub target_email_address_id: Option<Uuid>,
    pub target_email_address: Option<String>,
    pub user_id: Option<Uuid>,
    pub matched_via_plus_addressing: Option<bool>,
}

#[derive(Serialize)]
pub struct ReceiveEmailRequest {
    pub from: String,
    pub to: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub cc: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub bcc: Vec<String>,
    pub subject: Option<String>,
    pub body_text: Option<String>,
    pub body_html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub headers: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<Attachment>,
}

#[derive(Serialize, Clone)]
pub struct Attachment {
    pub filename: String,
    pub content_type: String,
    pub size_bytes: u64,
    pub content: String, // Base64 encoded
}

#[derive(Deserialize, Debug)]
pub struct ReceiveEmailResponse {
    pub status: String,
    pub message: String,
    pub delivered_to: Vec<DeliveryResult>,
}

#[derive(Deserialize, Debug)]
pub struct DeliveryResult {
    pub recipient: String,
    pub success: bool,
    pub email_id: Option<Uuid>,
    pub error: Option<String>,
}

impl ApiClient {
    pub fn new(base_url: String, service_key: String, secret_key: String) -> Self {
        Self {
            base_url,
            service_key,
            secret_key,
            client: reqwest::Client::new(),
        }
    }

    /// Generate HMAC-SHA256 signature for request
    fn generate_signature(
        &self,
        timestamp: u64,
        method: &str,
        path: &str,
        body: &str,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // Calculate body hash
        let mut hasher = Sha256::new();
        hasher.update(body.as_bytes());
        let body_hash = format!("{:x}", hasher.finalize());

        // Create message to sign: timestamp + method + path + body_hash
        let message = format!("{}{}{}{}", timestamp, method, path, body_hash);

        // Create HMAC
        let mut mac = HmacSha256::new_from_slice(self.secret_key.as_bytes())?;
        mac.update(message.as_bytes());
        let result = mac.finalize();
        let signature = format!("sha256={:x}", result.into_bytes());

        Ok(signature)
    }

    /// Get current Unix timestamp
    fn get_timestamp() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
    }

    /// Make authenticated POST request
    async fn post<T: Serialize, R: for<'de> Deserialize<'de>>(
        &self,
        path: &str,
        body: &T,
    ) -> Result<R, Box<dyn std::error::Error + Send + Sync>> {
        let timestamp = Self::get_timestamp();
        let body_json = serde_json::to_string(body)?;
        let signature = self.generate_signature(timestamp, "POST", path, &body_json)?;

        let url = format!("{}{}", self.base_url, path);

        let response = self.client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("X-Service-Key", &self.service_key)
            .header("X-Service-Signature", &signature)
            .header("X-Service-Timestamp", timestamp.to_string())
            .body(body_json)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_else(|_| "Unknown error".to_string());
            return Err(format!("API error {}: {}", status, error_text).into());
        }

        let result = response.json::<R>().await?;
        Ok(result)
    }

    /// Check if a domain exists and is active
    pub async fn lookup_domain(&self, domain: &str) -> Result<DomainLookupResponse, Box<dyn std::error::Error + Send + Sync>> {
        let request = DomainLookupRequest {
            domain: domain.to_string(),
        };
        self.post("/internal/lookup/domain", &request).await
    }

    /// Check if an email address exists
    pub async fn lookup_email(&self, email: &str) -> Result<EmailLookupResponse, Box<dyn std::error::Error + Send + Sync>> {
        let request = EmailLookupRequest {
            email: email.to_string(),
        };
        self.post("/internal/lookup/email", &request).await
    }

    /// Check if an email is an alias
    pub async fn lookup_alias(&self, email: &str) -> Result<AliasLookupResponse, Box<dyn std::error::Error + Send + Sync>> {
        let request = AliasLookupRequest {
            email: email.to_string(),
        };
        self.post("/internal/lookup/alias", &request).await
    }

    /// Send received email to API
    pub async fn receive_email(&self, request: ReceiveEmailRequest) -> Result<ReceiveEmailResponse, Box<dyn std::error::Error + Send + Sync>> {
        self.post("/internal/emails/receive", &request).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_signature_generation() {
        let client = ApiClient::new(
            "http://localhost:8080".to_string(),
            "srv_test_key".to_string(),
            "test_secret".to_string(),
        );

        let signature = client.generate_signature(
            1739577600,
            "POST",
            "/internal/lookup/domain",
            r#"{"domain":"example.com"}"#,
        ).unwrap();

        assert!(signature.starts_with("sha256="));
        assert_eq!(signature.len(), 71); // "sha256=" + 64 hex chars
    }
}

