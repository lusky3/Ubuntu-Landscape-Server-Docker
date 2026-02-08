#!/usr/bin/env bash
set -euo pipefail

LANDSCAPE_URL="${LANDSCAPE_URL:-https://landscape-server}"
ACCOUNT_NAME="${ACCOUNT_NAME:-standalone}"
COMPUTER_TITLE="${COMPUTER_TITLE:-$(hostname)}"

# Only configure if not already done
if [ ! -f /etc/landscape/.configured ]; then
  echo "Configuring Landscape client..."

  # Create config directory
  mkdir -p /etc/landscape

  # Wait for server to be ready
  echo "Waiting for server..."
  for _ in {1..30}; do
    if openssl s_client -connect landscape-server:443 </dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
      break
    fi
    sleep 2
  done

  # Fetch server certificate
  echo "Fetching server certificate..."
  openssl s_client -connect landscape-server:443 -showcerts </dev/null 2>/dev/null | \
    openssl x509 -outform PEM > /tmp/landscape-server.pem

  # Read registration key from shared volume if available
  if [ -f /var/lib/landscape/registration-key.txt ]; then
    REGISTRATION_KEY=$(cat /var/lib/landscape/registration-key.txt)
    echo "Using registration key from server"
  else
    REGISTRATION_KEY="${REGISTRATION_KEY:-}"
  fi

  # Write client config
  cat > /etc/landscape/client.conf <<EOF
[client]
url = $LANDSCAPE_URL/message-system
ping_url = $LANDSCAPE_URL/ping
account_name = $ACCOUNT_NAME
computer_title = $COMPUTER_TITLE
script_users = ALL
tags = container
log_level = info
ssl_public_key = /tmp/landscape-server.pem
EOF

  # Add registration key if provided
  if [ -n "$REGISTRATION_KEY" ]; then
    echo "registration_key = $REGISTRATION_KEY" >> /etc/landscape/client.conf
  fi

  touch /etc/landscape/.configured
fi

echo "Starting Landscape client..."
landscape-client &

# Keep container running
tail -f /var/log/landscape/sysinfo.log /var/log/landscape/watchdog.log 2>/dev/null || sleep infinity
