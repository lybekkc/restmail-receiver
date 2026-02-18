// Email parsing utilities
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct ParsedEmail {
    pub from: String,
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub bcc: Vec<String>,
    pub subject: Option<String>,
    pub body_text: Option<String>,
    pub body_html: Option<String>,
    pub headers: HashMap<String, String>,
}

impl ParsedEmail {
    pub fn new() -> Self {
        Self {
            from: String::new(),
            to: Vec::new(),
            cc: Vec::new(),
            bcc: Vec::new(),
            subject: None,
            body_text: None,
            body_html: None,
            headers: HashMap::new(),
        }
    }

    /// Parse email data from SMTP DATA command
    pub fn parse_from_data(email_data: &str) -> Self {
        let mut parsed = Self::new();
        let mut in_headers = true;
        let mut current_header_name = String::new();
        let mut current_header_value = String::new();
        let mut body = String::new();

        for line in email_data.lines() {
            if in_headers {
                if line.is_empty() {
                    // End of headers
                    if !current_header_name.is_empty() {
                        parsed.add_header(&current_header_name, &current_header_value);
                    }
                    in_headers = false;
                    continue;
                }

                // Check if this is a continuation line (starts with space or tab)
                if line.starts_with(' ') || line.starts_with('\t') {
                    current_header_value.push(' ');
                    current_header_value.push_str(line.trim());
                } else {
                    // New header
                    if !current_header_name.is_empty() {
                        parsed.add_header(&current_header_name, &current_header_value);
                    }

                    if let Some((name, value)) = line.split_once(':') {
                        current_header_name = name.trim().to_string();
                        current_header_value = value.trim().to_string();
                    }
                }
            } else {
                // Body content
                body.push_str(line);
                body.push('\n');
            }
        }

        // Set body (for now, just plain text)
        if !body.is_empty() {
            parsed.body_text = Some(body.trim().to_string());
        }

        parsed
    }

    fn add_header(&mut self, name: &str, value: &str) {
        let name_lower = name.to_lowercase();

        match name_lower.as_str() {
            "from" => {
                self.from = Self::extract_email(value);
            }
            "to" => {
                self.to = Self::parse_address_list(value);
            }
            "cc" => {
                self.cc = Self::parse_address_list(value);
            }
            "bcc" => {
                self.bcc = Self::parse_address_list(value);
            }
            "subject" => {
                self.subject = Some(value.to_string());
            }
            _ => {}
        }

        self.headers.insert(name.to_string(), value.to_string());
    }

    /// Extract email address from "Name <email@domain.com>" format
    fn extract_email(value: &str) -> String {
        if let Some(start) = value.find('<') {
            if let Some(end) = value.find('>') {
                return value[start + 1..end].to_string();
            }
        }
        value.trim().to_string()
    }

    /// Parse comma-separated address list
    fn parse_address_list(value: &str) -> Vec<String> {
        value
            .split(',')
            .map(|addr| Self::extract_email(addr.trim()))
            .filter(|addr| !addr.is_empty())
            .collect()
    }

    /// Extract domain from email address
    pub fn extract_domain(email: &str) -> Option<String> {
        email.split('@').nth(1).map(|s| s.to_lowercase())
    }

    /// Normalize email for plus addressing (remove +tag)
    pub fn normalize_email(email: &str) -> String {
        if let Some(at_pos) = email.find('@') {
            let (local, domain) = email.split_at(at_pos);
            if let Some(plus_pos) = local.find('+') {
                let (base, _tag) = local.split_at(plus_pos);
                return format!("{}{}", base, domain);
            }
        }
        email.to_string()
    }
}

impl Default for ParsedEmail {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_email() {
        assert_eq!(
            ParsedEmail::extract_email("John Doe <john@example.com>"),
            "john@example.com"
        );
        assert_eq!(
            ParsedEmail::extract_email("jane@example.com"),
            "jane@example.com"
        );
    }

    #[test]
    fn test_parse_address_list() {
        let addresses = ParsedEmail::parse_address_list(
            "John <john@example.com>, Jane <jane@example.com>"
        );
        assert_eq!(addresses, vec!["john@example.com", "jane@example.com"]);
    }

    #[test]
    fn test_extract_domain() {
        assert_eq!(
            ParsedEmail::extract_domain("user@example.com"),
            Some("example.com".to_string())
        );
        assert_eq!(ParsedEmail::extract_domain("invalid"), None);
    }

    #[test]
    fn test_normalize_email() {
        assert_eq!(
            ParsedEmail::normalize_email("user+tag@example.com"),
            "user@example.com"
        );
        assert_eq!(
            ParsedEmail::normalize_email("user@example.com"),
            "user@example.com"
        );
    }

    #[test]
    fn test_parse_simple_email() {
        let email_data = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Test\r\n\r\nBody content";
        let parsed = ParsedEmail::parse_from_data(email_data);

        assert_eq!(parsed.from, "sender@example.com");
        assert_eq!(parsed.to, vec!["recipient@example.com"]);
        assert_eq!(parsed.subject, Some("Test".to_string()));
        assert_eq!(parsed.body_text, Some("Body content".to_string()));
    }
}

