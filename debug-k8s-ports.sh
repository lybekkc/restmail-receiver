#!/bin/bash

# Debug script to test Kubernetes ports directly

echo "🔍 Testing Kubernetes NodePorts directly..."
echo ""

echo "1️⃣ Testing Policy Port 30345..."
echo "   Sending policy request to localhost:30345..."
response=$(timeout 3 bash -c '(echo "request=smtpd_access_policy
protocol_state=RCPT
recipient=test@restmail.org

") | nc localhost 30345' 2>&1)

if echo "$response" | grep -q "action=OK"; then
    echo "   ✅ Policy port 30345 works! Response: $response"
else
    echo "   ❌ Policy port 30345 failed or no response"
    echo "   Response: $response"
fi

echo ""
echo "2️⃣ Testing Delivery Port 30025..."
echo "   Connecting to localhost:30025..."
response=$(timeout 3 bash -c 'echo "QUIT" | nc localhost 30025' 2>&1)

if echo "$response" | grep -q "220.*ESMTP"; then
    echo "   ✅ Delivery port 30025 works! Got SMTP greeting"
else
    echo "   ❌ Delivery port 30025 failed or no response"
    echo "   Response: $response"
fi

echo ""
echo "3️⃣ Port accessibility check..."
nc -zv localhost 30345 2>&1
nc -zv localhost 30025 2>&1

echo ""
echo "4️⃣ Kubernetes service info..."
kubectl get svc restmail-service -o wide

echo ""
echo "5️⃣ Pod status..."
kubectl get pods -l app=restmail-receiver

echo ""
echo "✅ Now run the test with explicit ports:"
echo "   ./test_restmail.sh --mode kubernetes --host localhost --policy-port 30345 --delivery-port 30025"

