#!/usr/bin/env python3
"""
Restmail Receiver Test Utility (Python version)
Tests both policy service and mail delivery service
"""

import socket
import sys
import argparse
from datetime import datetime
from typing import Tuple

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color


def send_and_receive(host: str, port: int, data: str, timeout: int = 5) -> Tuple[bool, str]:
    """Send data to host:port and return response"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        sock.sendall(data.encode())

        response = b""
        while True:
            try:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                response += chunk
            except socket.timeout:
                break

        sock.close()
        return True, response.decode('utf-8', errors='ignore')
    except Exception as e:
        return False, str(e)


def test_policy(host: str, port: int, recipient: str, expected: str) -> bool:
    """Test the policy service"""
    print(f"{Colors.BLUE}Testing Policy Service...{Colors.NC}")
    print(f"  Recipient: {Colors.YELLOW}{recipient}{Colors.NC}")

    policy_request = f"""request=smtpd_access_policy
protocol_state=RCPT
protocol_name=ESMTP
client_address=192.0.2.1
client_name=mail.example.com
reverse_client_name=mail.example.com
helo_name=mail.example.com
sender=sender@example.com
recipient={recipient}

"""

    success, response = send_and_receive(host, port, policy_request)

    if not success:
        print(f"  {Colors.RED}✗ FAILED{Colors.NC} - Could not connect to policy service")
        print(f"    Error: {response}")
        return False

    if expected in response:
        print(f"  {Colors.GREEN}✓ PASSED{Colors.NC} - Got expected response: {expected}")
        return True
    else:
        print(f"  {Colors.RED}✗ FAILED{Colors.NC} - Unexpected response")
        print(f"    Expected: {expected}")
        print(f"    Got: {response[:200]}")
        return False


def test_mail_delivery(host: str, port: int, from_addr: str, to_addr: str, subject: str) -> bool:
    """Test mail delivery"""
    print(f"{Colors.BLUE}Testing Mail Delivery...{Colors.NC}")
    print(f"  From:    {Colors.YELLOW}{from_addr}{Colors.NC}")
    print(f"  To:      {Colors.YELLOW}{to_addr}{Colors.NC}")
    print(f"  Subject: {Colors.YELLOW}{subject}{Colors.NC}")

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    message_id = f"<test-{int(datetime.now().timestamp())}@test-client>"

    smtp_session = f"""EHLO test-client
MAIL FROM:<{from_addr}>
RCPT TO:<{to_addr}>
DATA
From: {from_addr}
To: {to_addr}
Subject: {subject}
Date: {timestamp}
Message-ID: {message_id}
Content-Type: text/plain; charset=utf-8

This is a test email sent by restmail test utility (Python version).

Test details:
- Timestamp: {timestamp}
- From: {from_addr}
- To: {to_addr}

If you're seeing this, the restmail-receiver is working correctly!
.
QUIT
"""

    success, response = send_and_receive(host, port, smtp_session, timeout=10)

    if not success:
        print(f"  {Colors.RED}✗ FAILED{Colors.NC} - Could not connect to mail delivery service")
        print(f"    Error: {response}")
        return False

    if "250 2.0.0 Ok: Queued" in response:
        print(f"  {Colors.GREEN}✓ PASSED{Colors.NC} - Email accepted and queued")
        return True
    else:
        print(f"  {Colors.RED}✗ FAILED{Colors.NC} - Email was not accepted")
        print(f"    Response: {response[:200]}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Test utility for restmail-receiver',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                                 # Test cargo run (local)
  %(prog)s --mode docker                   # Test docker deployment
  %(prog)s --mode kubernetes               # Test kubernetes deployment
  %(prog)s --host 192.168.1.100 --delivery-port 30025 --policy-port 30345
        """
    )

    parser.add_argument('--mode', choices=['local', 'docker', 'kubernetes'],
                       default='local', help='Test mode (default: local)')
    parser.add_argument('--host', default='localhost', help='Host to connect to (default: localhost)')
    parser.add_argument('--policy-port', type=int, help='Policy service port')
    parser.add_argument('--delivery-port', type=int, help='Mail delivery port')

    args = parser.parse_args()

    # Set default ports based on mode
    if args.policy_port is None:
        args.policy_port = 30345 if args.mode == 'kubernetes' else 12345

    if args.delivery_port is None:
        args.delivery_port = 30025 if args.mode == 'kubernetes' else 2525

    # Print header
    print(f"{Colors.BLUE}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.BLUE}║           Restmail Receiver Test Utility (Python)            ║{Colors.NC}")
    print(f"{Colors.BLUE}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print(f"{Colors.YELLOW}Configuration:{Colors.NC}")
    print(f"  Mode:          {Colors.GREEN}{args.mode}{Colors.NC}")
    print(f"  Host:          {Colors.GREEN}{args.host}{Colors.NC}")
    print(f"  Policy Port:   {Colors.GREEN}{args.policy_port}{Colors.NC}")
    print(f"  Delivery Port: {Colors.GREEN}{args.delivery_port}{Colors.NC}")
    print()

    # Run tests
    results = []

    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    print(f"{Colors.BLUE}  Test 1: Policy Service - Valid Domain{Colors.NC}")
    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    results.append(test_policy(args.host, args.policy_port, "user@restmail.org", "action=OK"))
    print()

    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    print(f"{Colors.BLUE}  Test 2: Policy Service - Invalid Domain{Colors.NC}")
    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    results.append(test_policy(args.host, args.policy_port, "user@example.com", "action=REJECT"))
    print()

    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    print(f"{Colors.BLUE}  Test 3: Mail Delivery - Send Test Email{Colors.NC}")
    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    results.append(test_mail_delivery(args.host, args.delivery_port,
                                     "test@example.com", "testuser@restmail.org",
                                     f"Test Email from {args.mode} mode"))
    print()

    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    print(f"{Colors.BLUE}  Test 4: Mail Delivery - Another Test Email{Colors.NC}")
    print(f"{Colors.BLUE}═══════════════════════════════════════════════════════════════{Colors.NC}")
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    results.append(test_mail_delivery(args.host, args.delivery_port,
                                     "sender@test.com", "john.doe@restmail.org",
                                     f"Integration Test {timestamp}"))
    print()

    # Summary
    passed = sum(results)
    total = len(results)

    if passed == total:
        print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.GREEN}║              All Tests Passed ({passed}/{total})                        ║{Colors.NC}")
        print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    else:
        print(f"{Colors.RED}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.RED}║         Some Tests Failed ({passed}/{total} passed)                   ║{Colors.NC}")
        print(f"{Colors.RED}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")

    print()
    print(f"{Colors.YELLOW}Note:{Colors.NC} Check the mail storage directory for saved emails:")

    if args.mode == 'local':
        print("  /var/mail/restmail/incoming/ (or path from config file)")
    elif args.mode == 'docker':
        print("  ./deploy/mail-storage/incoming/")
    elif args.mode == 'kubernetes':
        print("  /var/mail/restmail/incoming/ (on the node or PVC)")

    print()
    print(f"{Colors.BLUE}To view logs:{Colors.NC}")
    if args.mode == 'local':
        print("  tail -f /var/log/restmail-receiver/restmail.log")
        print("  (or check stdout if running with cargo run)")
    elif args.mode == 'docker':
        print("  docker logs -f restmail-receiver")
        print("  or check: ./deploy/logs/")
    elif args.mode == 'kubernetes':
        print("  kubectl logs -f deployment/restmail-receiver")

    # Exit with appropriate code
    sys.exit(0 if passed == total else 1)


if __name__ == '__main__':
    main()

