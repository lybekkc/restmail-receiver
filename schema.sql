-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id VARCHAR(255) UNIQUE NOT NULL, -- From OAuth2 provider
    oauth_provider VARCHAR(50) NOT NULL,
    oauth_domain VARCHAR(255) NOT NULL,
    display_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_external_id ON users(external_id);
CREATE INDEX idx_users_oauth_domain ON users(oauth_domain);

-- API Clients table (for REST_API_KEY tracking)
CREATE TABLE IF NOT EXISTS api_clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key VARCHAR(64) UNIQUE NOT NULL,
    api_key_hash VARCHAR(128) NOT NULL, -- bcrypt hash for secure storage
    client_name VARCHAR(255) NOT NULL,
    description TEXT,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at TIMESTAMP WITH TIME ZONE,
    usage_count BIGINT DEFAULT 0,
    rate_limit_per_hour INTEGER DEFAULT 1000,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_api_clients_key ON api_clients(api_key);
CREATE INDEX idx_api_clients_active ON api_clients(is_active);
CREATE INDEX idx_api_clients_created_by ON api_clients(created_by_user_id);

-- Mail domains table (for managing domains that can be used for email)
CREATE TABLE IF NOT EXISTS mail_domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    is_public BOOLEAN DEFAULT FALSE, -- If true, any user can create addresses on this domain
    requires_verification BOOLEAN DEFAULT TRUE,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_mail_domains_domain ON mail_domains(domain);
CREATE INDEX idx_mail_domains_is_active ON mail_domains(is_active);
CREATE INDEX idx_mail_domains_is_public ON mail_domains(is_public);

-- Email addresses for users
CREATE TABLE IF NOT EXISTS user_email_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email_address VARCHAR(255) NOT NULL,
    domain VARCHAR(255) NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, email_address),
    UNIQUE(user_id, domain) -- Ensures one email per domain per user
);

CREATE INDEX idx_user_emails_user_id ON user_email_addresses(user_id);
CREATE INDEX idx_user_emails_address ON user_email_addresses(email_address);
CREATE INDEX idx_user_emails_domain ON user_email_addresses(domain);

-- Email aliases
CREATE TABLE IF NOT EXISTS email_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    alias_address VARCHAR(255) NOT NULL,
    target_email_address_id UUID NOT NULL REFERENCES user_email_addresses(id) ON DELETE CASCADE,
    domain VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(alias_address)
);

CREATE INDEX idx_email_aliases_user_id ON email_aliases(user_id);
CREATE INDEX idx_email_aliases_address ON email_aliases(alias_address);

-- Labels (Gmail-style)
CREATE TABLE IF NOT EXISTS labels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7), -- Hex color code
    is_system BOOLEAN DEFAULT FALSE, -- System labels like INBOX, SENT, TRASH
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, name)
);

CREATE INDEX idx_labels_user_id ON labels(user_id);

-- Insert default system labels for each user (will be done via trigger or application logic)

-- Emails table
CREATE TABLE IF NOT EXISTS emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Email metadata
    subject VARCHAR(998), -- RFC 2822 limit
    from_address VARCHAR(255) NOT NULL,
    from_name VARCHAR(255),

    reply_to VARCHAR(255),

    -- Content
    body_text TEXT,
    body_html TEXT,

    -- Email State Flag
    is_read BOOLEAN DEFAULT FALSE,

    -- Soft delete support
    deleted_at TIMESTAMP WITH TIME ZONE,     -- If set, email is soft-deleted (for background cleanup)

    -- Snooze support
    snoozed_until TIMESTAMP WITH TIME ZONE,

    -- Thread support (for future)
    thread_id UUID,

    -- Timestamps
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_emails_user_id ON emails(user_id);
CREATE INDEX idx_emails_received_at ON emails(received_at DESC);
CREATE INDEX idx_emails_thread_id ON emails(thread_id);
CREATE INDEX idx_emails_snoozed ON emails(snoozed_until) WHERE snoozed_until IS NOT NULL;
CREATE INDEX idx_emails_deleted_at ON emails(deleted_at) WHERE deleted_at IS NOT NULL;

-- Email recipients (to support multiple recipients, cc, bcc)
CREATE TABLE IF NOT EXISTS email_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_id UUID NOT NULL REFERENCES emails(id) ON DELETE CASCADE,
    recipient_type VARCHAR(10) NOT NULL CHECK (recipient_type IN ('to', 'cc', 'bcc')),
    address VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_email_recipients_email_id ON email_recipients(email_id);

-- Email labels (many-to-many relationship)
CREATE TABLE IF NOT EXISTS email_labels (
    email_id UUID NOT NULL REFERENCES emails(id) ON DELETE CASCADE,
    label_id UUID NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (email_id, label_id)
);

CREATE INDEX idx_email_labels_email_id ON email_labels(email_id);
CREATE INDEX idx_email_labels_label_id ON email_labels(label_id);

-- Attachments table
CREATE TABLE IF NOT EXISTS attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_id UUID NOT NULL REFERENCES emails(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(127) NOT NULL,
    size_bytes BIGINT NOT NULL,
    file_path VARCHAR(512) NOT NULL, -- Path in filesystem or MinIO
    storage_type VARCHAR(20) DEFAULT 'filesystem' CHECK (storage_type IN ('filesystem', 'minio', 's3')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_attachments_email_id ON attachments(email_id);


-- Sent emails (emails composed and sent by users)
CREATE TABLE IF NOT EXISTS sent_emails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Email content
    subject VARCHAR(998),
    body_text TEXT,
    body_html TEXT,

    from_address VARCHAR(255) NOT NULL,
    from_name VARCHAR(255),

    -- Status tracking
    status VARCHAR(20) DEFAULT 'queued' CHECK (status IN ('queued', 'sending', 'sent', 'failed')),
    error_message TEXT,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sent_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sent_emails_user_id ON sent_emails(user_id);
CREATE INDEX idx_sent_emails_status ON sent_emails(status);
CREATE INDEX idx_sent_emails_created_at ON sent_emails(created_at DESC);

-- Sent email recipients
CREATE TABLE IF NOT EXISTS sent_email_recipients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sent_email_id UUID NOT NULL REFERENCES sent_emails(id) ON DELETE CASCADE,
    recipient_type VARCHAR(10) NOT NULL CHECK (recipient_type IN ('to', 'cc', 'bcc')),
    address VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sent_email_recipients_sent_email_id ON sent_email_recipients(sent_email_id);

-- Sent email attachments
CREATE TABLE IF NOT EXISTS sent_email_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sent_email_id UUID NOT NULL REFERENCES sent_emails(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(127) NOT NULL,
    size_bytes BIGINT NOT NULL,
    file_path VARCHAR(512) NOT NULL,
    storage_type VARCHAR(20) DEFAULT 'filesystem',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sent_email_attachments_sent_email_id ON sent_email_attachments(sent_email_id);

-- Contacts table (contact register for each user)
CREATE TABLE IF NOT EXISTS contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    company VARCHAR(255),
    phone VARCHAR(50),
    notes TEXT,
    is_favorite BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, email)
);

CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_email ON contacts(email);
CREATE INDEX idx_contacts_is_favorite ON contacts(is_favorite);
CREATE INDEX idx_contacts_name ON contacts(name) WHERE name IS NOT NULL;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_emails_updated_at BEFORE UPDATE ON emails
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sent_emails_updated_at BEFORE UPDATE ON sent_emails
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_api_clients_updated_at BEFORE UPDATE ON api_clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_mail_domains_updated_at BEFORE UPDATE ON mail_domains
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contacts_updated_at BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

