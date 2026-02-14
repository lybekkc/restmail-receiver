BINARY_NAME=restmail-receiver
INSTALL_PATH=/usr/local/bin/$(BINARY_NAME)

all: build

# Development setup
setup:
	@echo "Setting up local development environment..."
	./setup-dev.sh

# Quick dev: setup and run
dev: setup
	@echo "Starting development server..."
	cargo run

# Build for development (faster)
build-dev:
	cargo build

# Build for production (optimized)
build:
	cargo build --release

deploy: build
	@echo "--- Stopper tjenesten ---"
	-sudo systemctl stop $(BINARY_NAME)
	@echo "--- Installerer binærfil ---"
	sudo cp target/release/$(BINARY_NAME) $(INSTALL_PATH)
	sudo chmod +x $(INSTALL_PATH)
	@echo "--- Reloader systemd og starter ---"
	sudo systemctl daemon-reload
	sudo systemctl start $(BINARY_NAME)
	@echo "Deploy ferdig! Sjekk 'make status'"

# Simulerer en forespørsel fra Postfix (legacy)
test:
	@echo "Sender test-forespørsel til restmail-receiver..."
	@printf "request=smtpd_access_policy\nprotocol_state=RCPT\nrecipient=test@restmail.org\n\n" | nc 127.0.0.1 12345
	@echo "\nTest fullført."

# Run comprehensive tests
test-local:
	@echo "Running tests for local deployment..."
	./test_restmail.sh --mode local

test-docker:
	@echo "Running tests for Docker deployment..."
	./test_restmail.sh --mode docker

test-kubernetes:
	@echo "Running tests for Kubernetes deployment..."
	./test_restmail.sh --mode kubernetes

test-python:
	@echo "Running Python test utility..."
	./test_restmail.py --mode local

# Show test help
test-help:
	@echo "Available test targets:"
	@echo "  make test           - Quick policy service test (legacy)"
	@echo "  make test-local     - Test local/cargo run deployment"
	@echo "  make test-docker    - Test Docker deployment"
	@echo "  make test-kubernetes - Test Kubernetes deployment"
	@echo "  make test-python    - Run Python test utility"
	@echo ""
	@echo "For more options, see: ./test_restmail.sh --help"

status:
	sudo systemctl status $(BINARY_NAME)

logs:
	sudo journalctl -u $(BINARY_NAME) -f
