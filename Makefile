BINARY_NAME=restmail-receiver
INSTALL_PATH=/usr/local/bin/$(BINARY_NAME)

all: build

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

# Simulerer en forespørsel fra Postfix
test:
	@echo "Sender test-forespørsel til restmail-receiver..."
	@printf "request=smtpd_access_policy\nprotocol_state=RCPT\nrecipient=test@restmail.org\n\n" | nc 127.0.0.1 12345
	@echo "\nTest fullført."

status:
	sudo systemctl status $(BINARY_NAME)

logs:
	sudo journalctl -u $(BINARY_NAME) -f
