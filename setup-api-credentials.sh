#!/bin/bash

# Script to set up REST API credentials for testing
# This generates SQL to create service credentials in your PostgreSQL database

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     REST API Service Credentials Setup                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Generate random keys
API_KEY="srv_restmail_$(openssl rand -hex 24)"
SECRET_KEY="$(openssl rand -hex 32)"

echo "1️⃣  Generated Service Credentials:"
echo "   API Key:    $API_KEY"
echo "   Secret Key: $SECRET_KEY"
echo ""
echo "   ⚠️  IMPORTANT: Save the Secret Key now! It will be hashed in the database."
echo "   ⚠️  You won't be able to retrieve it later."
echo ""

echo "2️⃣  SQL to run on your PostgreSQL database:"
echo ""
cat << EOF
-- Create service credentials table if not exists
CREATE TABLE IF NOT EXISTS service_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_name VARCHAR(50) UNIQUE NOT NULL,
    api_key VARCHAR(64) UNIQUE NOT NULL,
    secret_key_hash VARCHAR(128) NOT NULL,  -- Note: stores hash, not plaintext
    is_active BOOLEAN DEFAULT TRUE,
    allowed_operations TEXT[],
    ip_whitelist TEXT[],
    last_used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE
);

-- Insert restmail-receiver service credentials
-- Note: Your REST API should hash the secret_key before storing
-- This is a placeholder - replace with your API's hash function
INSERT INTO service_credentials (
    service_name,
    api_key,
    secret_key_hash,
    is_active,
    allowed_operations
) VALUES (
    'restmail-receiver',
    '$API_KEY',
    -- TODO: Replace this with actual hash from your API
    -- Example: encode(digest('$SECRET_KEY', 'sha256'), 'hex')
    'HASH_THIS_SECRET_IN_YOUR_API',
    TRUE,
    ARRAY['lookup_domain', 'lookup_address', 'lookup_alias', 'receive_email']
)
ON CONFLICT (service_name)
DO UPDATE SET
    api_key = EXCLUDED.api_key,
    secret_key_hash = EXCLUDED.secret_key_hash,
    is_active = TRUE,
    allowed_operations = EXCLUDED.allowed_operations;

-- Query to verify
SELECT service_name, api_key, is_active, created_at
FROM service_credentials
WHERE service_name = 'restmail-receiver';
EOF

echo ""
echo "3️⃣  Better approach: Use your REST API to create the service account"
echo ""
echo "   If your REST API has an admin endpoint to create service credentials,"
echo "   use that instead. It will handle the hashing correctly."
echo ""
echo "   Example:"
cat << EOF
   curl -X POST http://localhost:8080/admin/service-credentials \\
     -H "Content-Type: application/json" \\
     -H "Authorization: Bearer \$ADMIN_TOKEN" \\
     -d '{
       "service_name": "restmail-receiver",
       "allowed_operations": ["lookup_domain", "lookup_address", "lookup_alias", "receive_email"]
     }'
EOF

echo ""
echo "4️⃣  After creating credentials in your API, update .env:"
echo ""
cat << EOF
# Update these lines in .env:
REST_API_URL=http://localhost:8080
REST_API_SERVICE_KEY=$API_KEY
REST_API_SECRET_KEY=$SECRET_KEY
EOF

echo ""
echo "5️⃣  Test the setup:"
echo ""
echo "   cargo run"
echo "   # Should show: ✅ API mode: ENABLED"
echo ""
echo "   ./test_restmail.sh"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📝 Note: The secret_key is NEVER stored in plaintext in the database."
echo "   Only the hash (secret_key_hash) is stored for security."
echo "   Your REST API validates by hashing the incoming key and comparing."
echo ""

