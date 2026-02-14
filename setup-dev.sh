#!/bin/bash

# Development Setup Script for Restmail Receiver
# This script sets up local development environment without requiring sudo

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🔧 Setting up Restmail Receiver for local development..."
echo ""

# Create development directories
echo "📁 Creating development directories..."
mkdir -p dev-storage/incoming
mkdir -p dev-logs

echo "   ✓ Created: dev-storage/incoming/ (for mail storage)"
echo "   ✓ Created: dev-logs/ (for log files)"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "📝 Creating .env file from .env.example..."
    cp .env.example .env
    echo "   ✓ Created: .env"
    echo ""
    echo "   Note: .env is configured for local development with user-writable paths."
    echo "   Edit .env if you need to change ports or paths."
else
    echo "ℹ️  .env file already exists - skipping"
fi
echo ""

# Check if directories are writable
echo "🔍 Checking directory permissions..."
if [ -w dev-storage/incoming ] && [ -w dev-logs ]; then
    echo "   ✓ Directories are writable"
else
    echo "   ⚠️  Warning: Directories may not be writable"
fi
echo ""

# Build the project
echo "🔨 Building the project..."
if cargo build; then
    echo "   ✓ Build successful"
else
    echo "   ✗ Build failed"
    exit 1
fi
echo ""

# Show configuration
echo "✅ Setup complete! Your configuration:"
echo ""
echo "   Mail storage:  ./dev-storage/incoming/"
echo "   Log files:     ./dev-logs/"
echo "   Policy port:   12345"
echo "   Delivery port: 2525"
echo ""

# Show next steps
echo "🚀 Next steps:"
echo ""
echo "   1. Start the server:"
echo "      cargo run"
echo ""
echo "   2. In another terminal, test it:"
echo "      ./test_restmail.sh"
echo ""
echo "   3. Check stored emails:"
echo "      ls -la dev-storage/incoming/"
echo ""
echo "   4. View logs:"
echo "      tail -f dev-logs/restmail.log"
echo "      (or check stdout from cargo run)"
echo ""
echo "📚 For more information, see:"
echo "   - README.md - General documentation"
echo "   - TESTING.md - Testing guide"
echo "   - ENV_VARS.md - Environment variable reference"
echo ""

# Add dev directories to .gitignore if not already there
if [ -f .gitignore ]; then
    if ! grep -q "dev-storage" .gitignore; then
        echo "" >> .gitignore
        echo "# Local development directories" >> .gitignore
        echo "dev-storage/" >> .gitignore
        echo "dev-logs/" >> .gitignore
        echo "   ✓ Added dev directories to .gitignore"
    fi
fi

