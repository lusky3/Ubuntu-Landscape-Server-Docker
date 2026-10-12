#!/usr/bin/env bash
set -euo pipefail

echo "==== Landscape entrypoint starting ===="

FQDN="${LANDSCAPE_FQDN:-landscape-server}"
CERT_PATH="/etc/ssl/certs/landscape_server.pem"
KEY_PATH="/etc/ssl/private/landscape_server.key"
# Landscape's Apache vhost serves this file as SSLCertificateChainFile
# (LANDSCAPE_CUSTOM_SSL_CA in Canonical's code), and mod_ssl uses it instead of
# any extra certificates in CERT_PATH, so ACME intermediates must be installed here.
CA_PATH="/etc/ssl/certs/landscape_server_ca.crt"
ACME_HOME="/opt/acme.sh"
# ACME CA to use; set ACME_SERVER=letsencrypt_test for Let's Encrypt staging.
ACME_SERVER="${ACME_SERVER:-letsencrypt}"

echo "Using FQDN: ${FQDN}"

generate_self_signed_cert() {
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
  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH"
}

# True if acme.sh already holds an issued certificate for $FQDN.
acme_cert_exists() {
  [ -s "${ACME_HOME}/${FQDN}/fullchain.cer" ] || [ -s "${ACME_HOME}/${FQDN}_ecc/fullchain.cer" ]
}

# Copy the acme.sh-managed certificate to where Apache expects it: the leaf in
# CERT_PATH and the intermediate chain in CA_PATH so clients can build the chain.
install_acme_cert() {
  "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --install-cert -d "$FQDN" \
    --key-file "$KEY_PATH" --cert-file "$CERT_PATH" --ca-file "$CA_PATH"
  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH" "$CA_PATH"
}

# Certificate generation
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "Generating SSL certificate..."
  ACME_OK=false

  if [ -n "${ACME_DNS_PROVIDER:-}" ]; then
    # Strip dns_ prefix if provided
    PROVIDER="${ACME_DNS_PROVIDER#dns_}"
    echo "Attempting ACME certificate (${ACME_SERVER}) with DNS authorization (${PROVIDER})..."

    # acme.sh DNS plugins read provider-native names (CF_Token, AWS_ACCESS_KEY_ID,
    # GD_Key, ...). They are supplied here as ACME_<name>, so strip the prefix.
    for var in $(compgen -e | grep '^ACME_' || true); do
      case "$var" in ACME_DNS_PROVIDER|ACME_SERVER) continue ;; esac
      export "${var#ACME_}=${!var}"
    done

    # acme.sh exits 2 when a still-valid certificate already exists; that is fine.
    acme_rc=0
    "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --issue --dns "dns_${PROVIDER}" \
      -d "$FQDN" --server "$ACME_SERVER" 2>&1 || acme_rc=$?
    if { [ "$acme_rc" -eq 0 ] || [ "$acme_rc" -eq 2 ]; } && install_acme_cert; then
      echo "ACME certificate installed"
      ACME_OK=true
    else
      echo "ERROR: ACME issuance failed (invalid provider '${PROVIDER}', missing credentials, or DNS/CA error)"
      echo "Falling back to self-signed certificate"
    fi
  fi

  if [ "$ACME_OK" != true ]; then
    generate_self_signed_cert
  fi
fi

# landscape-quickstart names the Apache vhost after the CN of the certificate
# above (<CN>.conf), so derive the path instead of assuming "localhost".
CERT_CN=$(openssl x509 -in "$CERT_PATH" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= *//p')
VHOST_CONF="/etc/apache2/sites-available/${CERT_CN:-$FQDN}.conf"

# Initialize PostgreSQL data directory if empty (first run with volume mount)
PG_VERSION=$(find /usr/lib/postgresql/ -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | head -1)
PG_DATA="/var/lib/postgresql/${PG_VERSION}/main"
if [ ! -d "$PG_DATA" ] || [ -z "$(ls -A "$PG_DATA" 2>/dev/null)" ]; then
  echo "PostgreSQL data directory empty - initializing cluster..."
  mkdir -p "$PG_DATA"
  chown -R postgres:postgres /var/lib/postgresql
  su postgres -c "/usr/lib/postgresql/${PG_VERSION}/bin/initdb -D $PG_DATA"
fi

echo "Starting PostgreSQL..."
service postgresql start

echo "Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  if su postgres -c "pg_isready" >/dev/null 2>&1; then
    echo "PostgreSQL is ready."
    break
  fi
  echo "  Waiting... ($i/30)"
  sleep 2
done

echo "Starting RabbitMQ..."
rabbitmq-server -detached
sleep 10

# Check if database exists - quickstart flag may persist on volume but DB is lost on rebuild
DB_EXISTS=false
if su postgres -c "psql -lqt" 2>/dev/null | cut -d \| -f 1 | grep -qw landscape-standalone-main; then
  DB_EXISTS=true
fi

if [ ! -f /var/lib/landscape/.quickstart_done ] || [ "$DB_EXISTS" = false ]; then
  if [ "$DB_EXISTS" = false ] && [ -f /var/lib/landscape/.quickstart_done ]; then
    echo "Database missing after container rebuild - re-running quickstart..."
    rm -f /var/lib/landscape/.quickstart_done
  fi
  echo "Running landscape-quickstart..."
  if ! landscape-quickstart --skip-ssl; then
    echo "ERROR: landscape-quickstart failed. Aborting startup." >&2
    exit 1
  fi
  
  # Fix Apache vhost rewrite - landscape-quickstart generates broken config
  sed -i 's|++vh++https:%{HTTP_HOST}:443/|++vh++https:%{SERVER_NAME}:443/|g' "$VHOST_CONF"
  sed -i 's|https://%{HTTP_HOST}:443/|https://%{HTTP_HOST}/|g' "$VHOST_CONF"
  
  # Fix 1: Add /ping rewrite to HTTPS VirtualHost
  echo "Adding /ping endpoint to HTTPS VirtualHost..."
  sed -i '/^    RewriteEngine On$/a\    RewriteRule ^/ping$ http://localhost:8070/ping [P,L]' "$VHOST_CONF"
  
  # Add /ping rewrite to HTTPS VirtualHost (after RewriteEngine On in the 443 vhost)
  echo "Adding /ping endpoint to HTTPS VirtualHost..."
  sed -i '/^<VirtualHost \*:443>/,/^<\/VirtualHost>/ {
    /RewriteEngine On/a\
\
    # Landscape Ping Server on port 8070\
    RewriteRule ^/ping$ http://localhost:8070/ping [P,L]
  }' "$VHOST_CONF"
  
  # Make sure the intended certificate is in place BEFORE starting services:
  # the ACME-issued one if we have it, otherwise a self-signed one with SANs.
  if acme_cert_exists; then
    echo "Re-installing ACME certificate..."
    install_acme_cert
  else
    echo "Regenerating SSL certificate with SAN..."
    generate_self_signed_cert
  fi

  # Create default admin account
  echo "Creating default admin account..."
  ADMIN_EMAIL="${ADMIN_EMAIL:-admin@landscape.local}"
  if [ -n "${ADMIN_PASSWORD:-}" ]; then
    echo "Using admin password from ADMIN_PASSWORD environment variable."
  else
    ADMIN_PASSWORD=$(openssl rand -base64 24)
    echo "Generated a random admin password (see /var/lib/landscape/admin-credentials.txt)."
  fi
  if ! /opt/canonical/landscape/bootstrap-account \
    --admin_email "$ADMIN_EMAIL" \
    --admin_password "$ADMIN_PASSWORD" \
    --admin_name "Admin User" \
    --root_url https://localhost; then
    echo "ERROR: bootstrap-account failed to create the admin user. Aborting startup." >&2
    exit 1
  fi
  cat > /var/lib/landscape/admin-credentials.txt <<CREDSEOF
email: $ADMIN_EMAIL
password: $ADMIN_PASSWORD
CREDSEOF
  chmod 600 /var/lib/landscape/admin-credentials.txt
  unset ADMIN_PASSWORD
  echo "Admin credentials written to /var/lib/landscape/admin-credentials.txt (root-only)."

  # Generate registration key for pre-enrollment
  echo "Generating registration key..."
  REGISTRATION_KEY=$(openssl rand -hex 16)
  echo "$REGISTRATION_KEY" > /var/lib/landscape/registration-key.txt
  chmod 640 /var/lib/landscape/registration-key.txt
  echo "Registration key saved to /var/lib/landscape/registration-key.txt"

  touch /var/lib/landscape/.quickstart_done
else
  echo "Skipping landscape-quickstart (already done)."
fi

# Start rsyslog for package-search service
echo "Starting rsyslog..."
rsyslogd || true
sleep 2

# Import Ubuntu archive GPG keys so hash-id generation can verify package indices
echo "Importing Ubuntu archive GPG keys..."
if ! gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/ubuntu-archive-runtime.gpg \
    --keyserver keyserver.ubuntu.com --recv-keys \
    40976EAF437D05B5 3B4FE6ACC0B21F32 871920D1991BC93C; then
  echo "WARNING: failed to import Ubuntu archive GPG keys; hash-id generation may fail to verify package indices." >&2
fi

# Generate hash-id databases for package reporting (run in background to avoid blocking startup)
if [ ! -f /var/lib/landscape/.hash_id_done ]; then
  if [ "${SKIP_HASH_ID_GENERATION:-false}" = "true" ]; then
    echo "Skipping hash-id database generation (SKIP_HASH_ID_GENERATION=true)"
    touch /var/lib/landscape/.hash_id_done
  else
    echo "Generating hash-id databases in background (this may take a few minutes)..."
    mkdir -p /var/lib/landscape/hash-id-databases
    (
      python3 /opt/canonical/landscape/hash-id-databases \
        --config /opt/canonical/landscape/configs/standalone/hash-id-databases.conf && \
      touch /var/lib/landscape/.hash_id_done && \
      echo "Hash-id database generation completed successfully."
    ) &
    HASH_ID_PID=$!
    echo "Hash-id generation running in background (PID: $HASH_ID_PID)"
  fi
else
  echo "Hash-id databases already generated."
fi

echo "Running database schema migration..."
if setup-landscape-server 2>&1; then
  echo "Schema migration completed successfully."
else
  echo "ERROR: Schema migration failed. Aborting startup." >&2
  exit 1
fi

echo "Starting Landscape services..."
# lsctl always exits non-zero in this container because landscape-package-search,
# landscape-hostagent-messenger, landscape-hostagent-consumer and
# landscape-secrets-service have no init.d script here (systemd-only units not
# applicable to this standalone image) - that's expected, so its exit code alone
# can't signal a real failure. Check the filtered output for actual failures instead.
LSCTL_OUTPUT=$(lsctl start 2>&1 | grep -v "unrecognized service" || true)
echo "$LSCTL_OUTPUT"
if echo "$LSCTL_OUTPUT" | grep -q "fail!"; then
  echo "ERROR: one or more Landscape services failed to start." >&2
  exit 1
fi

# Start package-search service (no init.d script, only systemd unit)
echo "Starting landscape-package-search..."
/opt/canonical/landscape/go/bin/packagesearch \
  -config /etc/landscape/service.conf &

# Fix CSP to allow localhost access
echo "Configuring CSP for localhost access..."
cat >> "$VHOST_CONF" <<'CSPEOF'

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
