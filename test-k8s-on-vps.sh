#!/bin/bash

# VPS Kubernetes Test Script
# Run this script ON YOUR VPS where Kubernetes is running

set -e

echo "🔍 Kubernetes Restmail Test (Run on VPS)"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Are you on the VPS with Kubernetes?"
    exit 1
fi

# Check if pod is running
echo "1️⃣ Checking pod status..."
POD_STATUS=$(kubectl get pods -l app=restmail-receiver -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
POD_NAME=$(kubectl get pods -l app=restmail-receiver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ "$POD_STATUS" = "Running" ]; then
    echo "   ✅ Pod is running: $POD_NAME"
else
    echo "   ❌ Pod is not running (status: $POD_STATUS)"
    kubectl get pods -l app=restmail-receiver
    exit 1
fi

echo ""
echo "2️⃣ Checking NodePort service..."
POLICY_PORT=$(kubectl get svc restmail-service -o jsonpath='{.spec.ports[?(@.name=="policy")].nodePort}' 2>/dev/null)
DELIVERY_PORT=$(kubectl get svc restmail-service -o jsonpath='{.spec.ports[?(@.name=="delivery")].nodePort}' 2>/dev/null)

if [ -z "$POLICY_PORT" ] || [ -z "$DELIVERY_PORT" ]; then
    echo "   ❌ Could not get NodePort values from service"
    kubectl get svc restmail-service
    exit 1
fi

echo "   ✅ Policy Port: $POLICY_PORT"
echo "   ✅ Delivery Port: $DELIVERY_PORT"

echo ""
echo "3️⃣ Testing Policy Service (port $POLICY_PORT)..."
POLICY_RESPONSE=$(timeout 5 bash -c "(echo 'request=smtpd_access_policy
protocol_state=RCPT
recipient=test@restmail.org

') | nc localhost $POLICY_PORT" 2>&1)

if echo "$POLICY_RESPONSE" | grep -q "action=OK"; then
    echo "   ✅ Policy service works! (Valid domain accepted)"
else
    echo "   ❌ Policy service failed"
    echo "   Response: $POLICY_RESPONSE"
fi

# Test reject
POLICY_RESPONSE_REJECT=$(timeout 5 bash -c "(echo 'request=smtpd_access_policy
protocol_state=RCPT
recipient=test@example.com

') | nc localhost $POLICY_PORT" 2>&1)

if echo "$POLICY_RESPONSE_REJECT" | grep -q "action=REJECT"; then
    echo "   ✅ Policy service works! (Invalid domain rejected)"
else
    echo "   ⚠️  Policy reject test unclear"
fi

echo ""
echo "4️⃣ Testing Mail Delivery (port $DELIVERY_PORT)..."
SMTP_RESPONSE=$(timeout 10 bash -c "(echo 'EHLO test
MAIL FROM:<test@example.com>
RCPT TO:<user@restmail.org>
DATA
Subject: K8s Test
Test email
.
QUIT') | nc localhost $DELIVERY_PORT" 2>&1)

if echo "$SMTP_RESPONSE" | grep -q "250 2.0.0 Ok: Queued"; then
    echo "   ✅ Mail delivery works! (Email queued)"
else
    echo "   ❌ Mail delivery failed or unclear"
    echo "   Response: $SMTP_RESPONSE" | head -10
fi

echo ""
echo "5️⃣ Checking stored emails in pod..."
EMAIL_COUNT=$(kubectl exec "$POD_NAME" -- sh -c 'ls /var/mail/restmail/incoming/*.eml 2>/dev/null | wc -l' 2>/dev/null || echo "0")
echo "   📧 Emails stored: $EMAIL_COUNT"

if [ "$EMAIL_COUNT" -gt "0" ]; then
    echo "   Latest email:"
    kubectl exec "$POD_NAME" -- sh -c 'ls -lt /var/mail/restmail/incoming/*.eml | head -1'
fi

echo ""
echo "6️⃣ Pod logs (last 10 lines)..."
kubectl logs "$POD_NAME" --tail=10

echo ""
echo "=========================================="
echo "✅ Test Summary:"
echo "   Pod Status:       Running ($POD_NAME)"
echo "   Policy Port:      $POLICY_PORT"
echo "   Delivery Port:    $DELIVERY_PORT"
echo "   Emails Stored:    $EMAIL_COUNT"
echo ""
echo "💡 To test from your local machine:"
echo "   ./test_restmail.sh --mode kubernetes --host <your-vps-ip> --policy-port $POLICY_PORT --delivery-port $DELIVERY_PORT"
echo ""
echo "🔐 If tests fail from external IP, check firewall:"
echo "   sudo ufw allow $POLICY_PORT/tcp"
echo "   sudo ufw allow $DELIVERY_PORT/tcp"
echo ""

