#!/usr/bin/env bash
set -euo pipefail

echo "==== Landscape entrypoint starting ===="

FQDN="${LANDSCAPE_FQDN:-landscape-server}"
CERT_PATH="/etc/ssl/certs/landscape_server.pem"
KEY_PATH="/etc/ssl/private/landscape_server.key"

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
  sed -i 's|https://%{HTTP_HOST}:443/|https://%{HTTP_HOST}/|g' /etc/apache2/sites-available/localhost.conf
  
  # Fix 1: Add /ping rewrite to HTTPS VirtualHost
  echo "Adding /ping endpoint to HTTPS VirtualHost..."
  sed -i '/^    RewriteEngine On$/a\    RewriteRule ^/ping$ http://localhost:8070/ping [P,L]' /etc/apache2/sites-available/localhost.conf
  
  # Add /ping rewrite to HTTPS VirtualHost (after RewriteEngine On in the 443 vhost)
  echo "Adding /ping endpoint to HTTPS VirtualHost..."
  sed -i '/^<VirtualHost \*:443>/,/^<\/VirtualHost>/ {
    /RewriteEngine On/a\
\
    # Landscape Ping Server on port 8070\
    RewriteRule ^/ping$ http://localhost:8070/ping [P,L]
  }' /etc/apache2/sites-available/localhost.conf
  
  # Regenerate certificate with correct SAN BEFORE starting services
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

# Start rsyslog for package-search service
echo "Starting rsyslog..."
rsyslogd || true
sleep 2

# Generate hash-id databases for package reporting
if [ ! -f /var/lib/landscape/.hash_id_done ]; then
  if [ "${SKIP_HASH_ID_GENERATION:-false}" = "true" ]; then
    echo "Skipping hash-id database generation (SKIP_HASH_ID_GENERATION=true)"
    touch /var/lib/landscape/.hash_id_done
  else
    echo "Generating hash-id databases (this may take a few minutes)..."
    mkdir -p /var/lib/landscape/hash-id-databases
    python3 /opt/canonical/landscape/hash-id-databases \
      --config /opt/canonical/landscape/configs/standalone/hash-id-databases.conf || true
    touch /var/lib/landscape/.hash_id_done
  fi
else
  echo "Hash-id databases already generated."
fi

echo "Starting Landscape services..."
lsctl start || true

# Start package-search service (no init.d script, only systemd unit)
echo "Starting landscape-package-search..."
/opt/canonical/landscape/go/bin/packagesearch \
  -config /etc/landscape/service.conf &

# Fix CSP to allow localhost access
echo "Configuring CSP for localhost access..."
cat >> /etc/apache2/sites-available/localhost.conf <<'CSPEOF'

<IfModule mod_headers.c>
  Header always set Content-Security-Policy "default-src 'self' https://localhost:* localhost:*; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://localhost:* localhost:* assets.ubuntu.com www.googletagmanager.com www.google-analytics.com script.crazyegg.com www.google.com www.google.ca https://*.maze.co/; style-src 'self' 'unsafe-inline' https://localhost:* localhost:* assets.ubuntu.com https://*.maze.co/; img-src 'self' https://localhost:* localhost:* assets.ubuntu.com data: www.googletagmanager.com www.google-analytics.com script.crazyegg.com www.google.com www.google.ca https://*.maze.co/; connect-src 'self' https://localhost:* localhost:* https://*.maze.co/"
</IfModule>
CSPEOF

if pgrep -x apache2 >/dev/null 2>&1; then
  echo "Stopping background Apache..."
  apachectl -k stop || true
fi

echo "Starting Apache in foreground..."
exec apachectl -D FOREGROUND
