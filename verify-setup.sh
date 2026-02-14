#!/bin/bash

# Quick Verification Script
# Run this to verify everything is working

cd "$(dirname "$0")"

echo "🔍 Verifying restmail-receiver setup..."
echo ""

# 1. Check .env exists
if [ -f .env ]; then
    echo "✅ .env file exists"
else
    echo "❌ .env file missing - run ./setup-dev.sh first"
    exit 1
fi

# 2. Check directories exist
if [ -d dev-storage/incoming ] && [ -d dev-logs ]; then
    echo "✅ Development directories exist"
else
    echo "❌ Development directories missing - run ./setup-dev.sh first"
    exit 1
fi

# 3. Check binary exists
if cargo build --quiet 2>&1; then
    echo "✅ Project builds successfully"
else
    echo "❌ Build failed"
    exit 1
fi

# 4. Try to start server
echo ""
echo "🚀 Starting server for 2 seconds..."
timeout 2 cargo run > /tmp/verify-test.log 2>&1 || true

# 5. Check if it started without permission errors
if grep -q "Permission denied" /tmp/verify-test.log; then
    echo "❌ Permission error found"
    cat /tmp/verify-test.log
    exit 1
else
    echo "✅ No permission errors"
fi

if grep -q "Restmail System Aktivt" /tmp/verify-test.log; then
    echo "✅ Server started successfully"
else
    echo "⚠️  Server may not have started (check log)"
    cat /tmp/verify-test.log
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          ✅ Everything looks good!                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "To start the server:"
echo "  cargo run"
echo ""
echo "To test it (in another terminal):"
echo "  ./test_restmail.sh"
echo ""
echo "To check saved emails:"
echo "  ls -la dev-storage/incoming/"
echo ""

