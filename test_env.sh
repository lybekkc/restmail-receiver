#!/bin/bash
echo "Testing environment variable configuration..."
echo ""
# Set environment variables
export RESTMAIL_POLICY_PORT=9999
export RESTMAIL_DELIVERY_PORT=8888
export RESTMAIL_LISTEN_ADDRESS=127.0.0.1
export RESTMAIL_STORAGE_BASE_PATH=/tmp/test-mail
export RESTMAIL_STORAGE_INCOMING=test-incoming
echo "Environment variables set:"
echo "RESTMAIL_POLICY_PORT=$RESTMAIL_POLICY_PORT"
echo "RESTMAIL_DELIVERY_PORT=$RESTMAIL_DELIVERY_PORT"
echo "RESTMAIL_LISTEN_ADDRESS=$RESTMAIL_LISTEN_ADDRESS"
echo "RESTMAIL_STORAGE_BASE_PATH=$RESTMAIL_STORAGE_BASE_PATH"
echo "RESTMAIL_STORAGE_INCOMING=$RESTMAIL_STORAGE_INCOMING"
echo ""
echo "You can now run: ./target/release/restmail-receiver"
echo "It should load configuration from environment variables."
