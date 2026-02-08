#!/usr/bin/env bash
set -euo pipefail

echo "==== Landscape entrypoint starting ===="

FQDN="${LANDSCAPE_FQDN:-landscape-server}"
CERT_PATH="/etc/ssl/certs/landscape.crt"
KEY_PATH="/etc/ssl/private/landscape.key"

echo "Using FQDN: ${FQDN}"

# Certificate generation
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "Generating SSL certificate..."
  
  if [ -n "${ACME_DNS_PROVIDER:-}" ]; then
    # Strip dns_ prefix if provided
    PROVIDER="${ACME_DNS_PROVIDER#dns_}"
    echo "Attempting Let's Encrypt with DNS authorization (${PROVIDER})..."
    curl -s https://get.acme.sh | sh -s
    
    # Export all ACME_* env vars for the DNS provider
    for var in $(env | grep '^ACME_' | cut -d= -f1); do
      [ "$var" != "ACME_DNS_PROVIDER" ] && export "${var?}"
    done
    
    if ~/.acme.sh/acme.sh --issue --dns "dns_${PROVIDER}" -d "$FQDN" --server letsencrypt 2>&1; then
      ~/.acme.sh/acme.sh --install-cert -d "$FQDN" --cert-file "$CERT_PATH" --key-file "$KEY_PATH" --fullchain-file /etc/ssl/certs/landscape-fullchain.crt
      echo "Let's Encrypt certificate installed"
    else
      echo "ERROR: Let's Encrypt failed (invalid provider '${PROVIDER}' or missing credentials)"
      echo "Falling back to self-signed certificate"
      ACME_DNS_PROVIDER=""
    fi
  fi
  
  if [ -z "${ACME_DNS_PROVIDER:-}" ]; then
    echo "Generating self-signed certificate..."
    cat > /tmp/san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $FQDN

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $FQDN
DNS.2 = landscape-server
DNS.3 = localhost
EOF
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout "$KEY_PATH" -out "$CERT_PATH" \
      -config /tmp/san.cnf -extensions v3_req
  fi
  
  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH"
fi

echo "Starting PostgreSQL..."
service postgresql start
sleep 5

echo "Starting RabbitMQ..."
rabbitmq-server -detached
sleep 10

if [ ! -f /var/lib/landscape/.quickstart_done ]; then
  echo "Running landscape-quickstart..."
  landscape-quickstart --skip-ssl || true
  
  # Fix Apache vhost rewrite - landscape-quickstart generates broken config
  sed -i 's|++vh++https:%{HTTP_HOST}:443/|++vh++https:%{SERVER_NAME}:443/|g' /etc/apache2/sites-available/localhost.conf
  
  # Create default admin account
  echo "Creating default admin account..."
  /opt/canonical/landscape/bootstrap-account \
    --admin_email admin@landscape.local \
    --admin_password admin \
    --admin_name "Admin User" \
    --root_url https://localhost || true
  
  # Generate registration key for pre-enrollment
  echo "Generating registration key..."
  REGISTRATION_KEY=$(openssl rand -hex 16)
  echo "$REGISTRATION_KEY" > /var/lib/landscape/registration-key.txt
  chmod 644 /var/lib/landscape/registration-key.txt
  echo "Registration key saved to /var/lib/landscape/registration-key.txt"
  
  touch /var/lib/landscape/.quickstart_done
else
  echo "Skipping landscape-quickstart (already done)."
fi

# Always regenerate certificate with correct SAN
echo "Regenerating SSL certificate with SAN..."
cat > /tmp/san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $FQDN

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $FQDN
DNS.2 = landscape-server
DNS.3 = localhost
EOF
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$KEY_PATH" -out "$CERT_PATH" \
  -config /tmp/san.cnf -extensions v3_req
chmod 600 "$KEY_PATH"
chmod 644 "$CERT_PATH"

# Reload Apache if it's running
if pgrep -x apache2 >/dev/null 2>&1; then
  echo "Reloading Apache to use new certificate..."
  apachectl graceful || true
fi

echo "Starting Landscape services..."
lsctl start || true

if pgrep -x apache2 >/dev/null 2>&1; then
  echo "Stopping background Apache..."
  apachectl -k stop || true
fi

echo "Starting Apache in foreground..."
exec apachectl -D FOREGROUND
