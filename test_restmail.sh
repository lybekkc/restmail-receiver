#!/bin/bash

# Restmail Receiver Test Utility
# This script tests both the policy service (port 12345) and mail delivery (port 2525)
# Works with cargo run, docker, and kubernetes deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
POLICY_PORT=12345
DELIVERY_PORT=2525
HOST="localhost"
MODE="local"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --policy-port)
            POLICY_PORT="$2"
            shift 2
            ;;
        --delivery-port)
            DELIVERY_PORT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --mode <local|docker|kubernetes>  Test mode (default: local)"
            echo "  --host <hostname>                  Host to connect to (default: localhost)"
            echo "  --policy-port <port>               Policy service port (default: 12345)"
            echo "  --delivery-port <port>             Mail delivery port (default: 2525)"
            echo "  --help                             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                 # Test cargo run (local)"
            echo "  $0 --mode docker                   # Test docker deployment"
            echo "  $0 --mode kubernetes               # Test kubernetes deployment"
            echo "  $0 --host 192.168.1.100 --delivery-port 30025 --policy-port 30345"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set ports based on mode if not explicitly specified
case $MODE in
    local)
        # cargo run uses default ports from config or env vars
        POLICY_PORT=${POLICY_PORT:-12345}
        DELIVERY_PORT=${DELIVERY_PORT:-2525}
        ;;
    docker)
        # docker-compose exposes the same ports
        POLICY_PORT=${POLICY_PORT:-12345}
        DELIVERY_PORT=${DELIVERY_PORT:-2525}
        ;;
    kubernetes)
        # kubernetes uses NodePort 30025 and 30345
        POLICY_PORT=${POLICY_PORT:-30345}
        DELIVERY_PORT=${DELIVERY_PORT:-30025}
        ;;
esac

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Restmail Receiver Test Utility                     ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Mode:          ${GREEN}$MODE${NC}"
echo -e "  Host:          ${GREEN}$HOST${NC}"
echo -e "  Policy Port:   ${GREEN}$POLICY_PORT${NC}"
echo -e "  Delivery Port: ${GREEN}$DELIVERY_PORT${NC}"
echo ""

# Test 1: Policy Service - Valid recipient
test_policy() {
    local recipient=$1
    local expected=$2

    echo -e "${BLUE}Testing Policy Service...${NC}"
    echo -e "  Recipient: ${YELLOW}$recipient${NC}"

    # Create policy request (Postfix policy delegation protocol)
    local policy_request="request=smtpd_access_policy
protocol_state=RCPT
protocol_name=ESMTP
client_address=192.0.2.1
client_name=mail.example.com
reverse_client_name=mail.example.com
helo_name=mail.example.com
sender=sender@example.com
recipient=$recipient

"

    # Send request
    response=$(echo -e "$policy_request" | nc -w 5 $HOST $POLICY_PORT 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}✗ FAILED${NC} - Could not connect to policy service"
        echo -e "    Error: $response"
        return 1
    fi

    if echo "$response" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓ PASSED${NC} - Got expected response: $expected"
        return 0
    else
        echo -e "  ${RED}✗ FAILED${NC} - Unexpected response"
        echo -e "    Expected: $expected"
        echo -e "    Got: $response"
        return 1
    fi
}

# Test 2: Send test email
test_mail_delivery() {
    local from=$1
    local to=$2
    local subject=$3

    echo -e "${BLUE}Testing Mail Delivery...${NC}"
    echo -e "  From:    ${YELLOW}$from${NC}"
    echo -e "  To:      ${YELLOW}$to${NC}"
    echo -e "  Subject: ${YELLOW}$subject${NC}"

    # Create SMTP conversation
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local smtp_session="EHLO test-client
MAIL FROM:<$from>
RCPT TO:<$to>
DATA
From: $from
To: $to
Subject: $subject
Date: $timestamp
Message-ID: <test-$(date +%s)@test-client>
Content-Type: text/plain; charset=utf-8

This is a test email sent by restmail test utility.

Test details:
- Mode: $MODE
- Timestamp: $timestamp
- From: $from
- To: $to

If you're seeing this, the restmail-receiver is working correctly!
.
QUIT
"

    # Send email
    response=$(echo -e "$smtp_session" | nc -w 10 $HOST $DELIVERY_PORT 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo -e "  ${RED}✗ FAILED${NC} - Could not connect to mail delivery service"
        echo -e "    Error: $response"
        return 1
    fi

    if echo "$response" | grep -q "250 2.0.0 Ok: Queued"; then
        echo -e "  ${GREEN}✓ PASSED${NC} - Email accepted and queued"
        return 0
    else
        echo -e "  ${RED}✗ FAILED${NC} - Email was not accepted"
        echo -e "    Response: $response"
        return 1
    fi
}

# Check if netcat is available
if ! command -v nc &> /dev/null; then
    echo -e "${RED}Error: netcat (nc) is required but not installed${NC}"
    echo "Please install it with: brew install netcat (macOS) or apt-get install netcat (Linux)"
    exit 1
fi

# Run tests
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test 1: Policy Service - Valid Domain${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
test_policy "user@restmail.org" "action=OK"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test 2: Policy Service - Invalid Domain${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
test_policy "user@example.com" "action=REJECT"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test 3: Mail Delivery - Send Test Email${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
test_mail_delivery "test@example.com" "testuser@restmail.org" "Test Email from $MODE mode"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test 4: Mail Delivery - Another Test Email${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
test_mail_delivery "sender@test.com" "john.doe@restmail.org" "Integration Test $(date +%Y%m%d-%H%M%S)"
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    All Tests Completed                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} Check the mail storage directory for saved emails:"

case $MODE in
    local)
        if [ -n "$RESTMAIL_STORAGE_BASE_PATH" ]; then
            echo "  $RESTMAIL_STORAGE_BASE_PATH/incoming/"
        else
            echo "  /var/mail/restmail/incoming/ (or path from config file)"
        fi
        ;;
    docker)
        echo "  ./deploy/mail-storage/incoming/"
        ;;
    kubernetes)
        echo "  /var/mail/restmail/incoming/ (on the node or PVC)"
        ;;
esac

echo ""
echo -e "${BLUE}To view logs:${NC}"
case $MODE in
    local)
        echo "  tail -f /var/log/restmail-receiver/restmail.log"
        echo "  (or check stdout if running with cargo run)"
        ;;
    docker)
        echo "  docker logs -f restmail-receiver"
        echo "  or check: ./deploy/logs/"
        ;;
    kubernetes)
        echo "  kubectl logs -f deployment/restmail-receiver"
        ;;
esac

