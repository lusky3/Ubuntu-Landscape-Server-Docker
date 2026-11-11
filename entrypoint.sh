#!/usr/bin/env bash
# Entrypoint for the single-container Landscape 26.04 server.
#
# Landscape 26.04 dropped its SysV init scripts and is managed only through
# systemd units, which cannot run in a plain container. Instead, supervisord
# (see supervisord.conf) runs PostgreSQL, RabbitMQ, Apache, cron and every
# service from landscape-server.target. This script does first-run
# provisioning, then hands control to supervisord and waits for it.
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
DATA_DIR="/var/lib/landscape"
STATE_DIR="${DATA_DIR}/.state"
STATE_TAR="${STATE_DIR}/config.tar"
# Lives in the container layer (not on a volume): present after "docker restart",
# absent in a brand-new container that reuses the volumes.
RESTORED_MARKER="/var/lib/.ls-state-restored"
SUP_CONF="/etc/supervisor/supervisord.conf"

echo "Using FQDN: ${FQDN}"

supctl() { supervisorctl -c "$SUP_CONF" "$@"; }

# --------------------------------------------------------------------- state
# Configuration that landscape-quickstart writes outside the data volumes
# (service.conf with its secrets, the Apache vhost, pg_hba.conf, certificates)
# is archived into the landscape volume so a new container on the same volumes
# comes back with the same configuration.
STATE_PATHS=(
  etc/landscape
  etc/apache2
  var/lib/apache2/site
  etc/postgresql
  etc/ssl/certs/landscape_server.pem
  etc/ssl/certs/landscape_server_ca.crt
  etc/ssl/private/landscape_server.key
  opt/acme.sh
)

save_state() {
  local existing=() p
  mkdir -p "$STATE_DIR"
  for p in "${STATE_PATHS[@]}"; do
    [ -e "/$p" ] && existing+=("$p")
  done
  tar -C / -cf "${STATE_TAR}.new" "${existing[@]}" && mv -f "${STATE_TAR}.new" "$STATE_TAR"
  chmod 600 "$STATE_TAR"
}

restore_state() {
  if [ -f "$STATE_TAR" ] && [ ! -f "$RESTORED_MARKER" ]; then
    echo "Restoring saved configuration from ${STATE_TAR}..."
    tar -C / -xpf "$STATE_TAR"
  fi
  touch "$RESTORED_MARKER"
}

# --------------------------------------------------------------- certificates
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

ensure_certificate() {
  if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    return 0
  fi
  echo "Generating SSL certificate..."
  local acme_ok=false
  if [ -n "${ACME_DNS_PROVIDER:-}" ]; then
    # Strip dns_ prefix if provided
    local provider="${ACME_DNS_PROVIDER#dns_}" var
    echo "Attempting ACME certificate (${ACME_SERVER}) with DNS authorization (${provider})..."

    # acme.sh DNS plugins read provider-native names (CF_Token, AWS_ACCESS_KEY_ID,
    # GD_Key, ...). They are supplied here as ACME_<name>, so strip the prefix.
    for var in $(compgen -e | grep '^ACME_' || true); do
      case "$var" in ACME_DNS_PROVIDER|ACME_SERVER) continue ;; esac
      export "${var#ACME_}=${!var}"
    done

    # acme.sh exits 2 when a still-valid certificate already exists; that is fine.
    local acme_rc=0
    "${ACME_HOME}/acme.sh" --home "$ACME_HOME" --issue --dns "dns_${provider}" \
      -d "$FQDN" --server "$ACME_SERVER" 2>&1 || acme_rc=$?
    if { [ "$acme_rc" -eq 0 ] || [ "$acme_rc" -eq 2 ]; } && install_acme_cert; then
      echo "ACME certificate installed"
      acme_ok=true
    else
      echo "ERROR: ACME issuance failed (invalid provider '${provider}', missing credentials, or DNS/CA error)"
      echo "Falling back to self-signed certificate"
    fi
  fi
  if [ "$acme_ok" != true ]; then
    generate_self_signed_cert
  fi
}

# ------------------------------------------------------------------ services
wait_for() { # wait_for <description> <tries> <command...>
  local what="$1" tries="$2"
  shift 2
  for _ in $(seq 1 "$tries"); do
    if "$@" >/dev/null 2>&1; then
      echo "${what} is ready."
      return 0
    fi
    sleep 2
  done
  echo "ERROR: timed out waiting for ${what}" >&2
  return 1
}

# Idempotently (re)create the RabbitMQ vhosts/user that service.conf points to.
# RabbitMQ state is not persisted, so this runs on every start.
provision_rabbitmq() {
  local user password vhost hvhost
  # Use Landscape's own settings loader: service.conf may store the password
  # base64-encoded ("b64:...") and the broker needs the decoded value.
  {
    read -r user
    read -r password
    read -r vhost
    read -r hvhost
  } < <(/opt/venvs/landscape/bin/python3 -c '
from canonical.landscape import settings
from canonical.lib.text import password_decode
b = settings.get_settings().broker
print(b.user)
print(password_decode(b.password) if b.password else "")
print(b.vhost)
print(b.hostagent_virtual_host)
')
  if [ -z "$password" ]; then
    echo "ERROR: no broker password in /etc/landscape/service.conf" >&2
    return 1
  fi
  local v
  for v in "$vhost" "$hvhost"; do
    rabbitmqctl list_vhosts -q | grep -qx "$v" || rabbitmqctl add_vhost "$v"
  done
  if rabbitmqctl list_users -q | cut -f1 | grep -qx "$user"; then
    rabbitmqctl change_password "$user" "$password"
  else
    rabbitmqctl add_user "$user" "$password"
  fi
  for v in "$vhost" "$hvhost"; do
    rabbitmqctl set_permissions -p "$v" "$user" '.*' '.*' '.*'
  done
}

init_postgres_cluster() {
  local pgv pgdata
  pgv=$(find /usr/lib/postgresql/ -maxdepth 1 -mindepth 1 -printf '%f\n' | sort -n | tail -1)
  pgdata="/var/lib/postgresql/${pgv}/main"
  if [ ! -s "${pgdata}/PG_VERSION" ]; then
    echo "PostgreSQL data directory empty - initializing cluster..."
    mkdir -p "$pgdata"
    chown -R postgres:postgres /var/lib/postgresql
    chmod 700 "$pgdata"
    runuser -u postgres -- "/usr/lib/postgresql/${pgv}/bin/initdb" -D "$pgdata"
  fi
  chown -R postgres:postgres /var/lib/postgresql
  mkdir -p /run/postgresql
  chown postgres:postgres /run/postgresql
}

# The generated vhost only proxies /ping on the plain-HTTP (port 80) vhost, which
# redirects everything else to HTTPS. Add it to the HTTPS vhost as well so that
# https://<host>/ping (used by the healthcheck) reaches the ping server.
fixup_vhost() {
  local cn vhost_conf
  cn=$(openssl x509 -in "$CERT_PATH" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= *//p')
  vhost_conf="/etc/apache2/sites-available/${cn:-localhost}.conf"
  if [ ! -f "$vhost_conf" ]; then
    echo "WARNING: expected Apache vhost ${vhost_conf} not found" >&2
    return 0
  fi
  if ! grep -q 'ls-container: https ping' "$vhost_conf"; then
    echo "Adding /ping to the HTTPS VirtualHost..."
    sed -i '/^<VirtualHost \*:443>/,/^<\/VirtualHost>/ {
      /^ *RewriteEngine On/a\
    # ls-container: https ping\
    RewriteRule ^/ping$ http://localhost:8070/ping [P,L]
    }' "$vhost_conf"
  fi
}

run_first_time_setup() {
  local db_exists=false
  if runuser -u postgres -- psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw landscape-standalone-main; then
    db_exists=true
  fi

  if [ -f "${DATA_DIR}/.quickstart_done" ] && [ "$db_exists" = true ] && [ -s /etc/landscape/service.conf ]; then
    echo "Skipping landscape-quickstart (already done)."
    return 0
  fi
  if [ -f "${DATA_DIR}/.quickstart_done" ]; then
    echo "Database or configuration missing - re-running quickstart..."
    rm -f "${DATA_DIR}/.quickstart_done"
  fi

  echo "Running landscape-quickstart..."
  if ! landscape-quickstart --skip-ssl; then
    echo "ERROR: landscape-quickstart failed. Aborting startup." >&2
    return 1
  fi
  provision_rabbitmq

  # Make sure the intended certificate is in place BEFORE starting services:
  # the ACME-issued one if we have it, otherwise a self-signed one with SANs.
  if acme_cert_exists; then
    echo "Re-installing ACME certificate..."
    install_acme_cert
  else
    echo "Regenerating SSL certificate with SAN..."
    generate_self_signed_cert
  fi

  echo "Creating default admin account..."
  local admin_email="${ADMIN_EMAIL:-admin@landscape.example}" admin_password
  if [ -n "${ADMIN_PASSWORD:-}" ]; then
    echo "Using admin password from ADMIN_PASSWORD environment variable."
    admin_password="$ADMIN_PASSWORD"
  else
    admin_password=$(openssl rand -base64 24)
    echo "Generated a random admin password (see ${DATA_DIR}/admin-credentials.txt)."
  fi
  if ! /opt/canonical/landscape/bootstrap-account \
    --admin_email "$admin_email" \
    --admin_password "$admin_password" \
    --admin_name "Admin User" \
    --root_url "https://${FQDN}"; then
    echo "ERROR: bootstrap-account failed to create the admin user. Aborting startup." >&2
    return 1
  fi
  cat > "${DATA_DIR}/admin-credentials.txt" <<CREDSEOF
email: $admin_email
password: $admin_password
CREDSEOF
  chmod 600 "${DATA_DIR}/admin-credentials.txt"
  echo "Admin credentials written to ${DATA_DIR}/admin-credentials.txt (root-only)."

  echo "Generating registration key..."
  openssl rand -hex 16 > "${DATA_DIR}/registration-key.txt"
  chmod 640 "${DATA_DIR}/registration-key.txt"

  touch "${DATA_DIR}/.quickstart_done"
}

# Set keys in the [features] section of service.conf (edited in place so the
# file's owner and mode are kept). Usage: set_features key=value...
# An empty value removes the key.
set_features() {
  python3 -I - /etc/landscape/service.conf "$@" <<'PY'
import sys

conf, *pairs = sys.argv[1:]
with open(conf, "r+") as f:
    lines = f.read().split("\n")
    if "[features]" not in lines:
        lines += ["", "[features]", ""]
    for pair in pairs:
        key, value = pair.split("=", 1)
        start = lines.index("[features]") + 1
        end = start
        while end < len(lines) and not lines[end].startswith("["):
            end += 1
        for i in range(start, end):
            if lines[i].split("=")[0].strip() == key:
                if value:
                    lines[i] = f"{key} = {value}"
                else:
                    del lines[i]
                break
        else:
            if value:
                lines.insert(start, f"{key} = {value}")
    f.seek(0)
    f.write("\n".join(lines))
    f.truncate()
PY
}

# Outbox (needs the landscape-outbox service), computer soft deletion (which
# relies on the outbox), repository mirrors and Ubuntu Pro licensing all default to on; set the
# matching variable to "false" to disable. Pro licensing is what lets computers
# be accepted without a seat-based license file (legacy seats still take
# precedence when /etc/landscape/license.txt is present).
configure_features() {
  local outbox="${LANDSCAPE_ENABLE_OUTBOX:-true}" soft="${LANDSCAPE_ENABLE_SOFT_DELETION:-true}"
  local pro="${LANDSCAPE_ENABLE_PRO_LICENSING:-true}" mirrors=""
  # Repository mirrors (served by the landscape-debarchive service). Landscape
  # 26.04 reads this flag as an unrecognised service.conf key: any value enables
  # it (and logs a harmless "invalid and ignored" warning), so only write it when on.
  if [ "${LANDSCAPE_ENABLE_REPOSITORY_MIRRORS:-true}" = "true" ]; then mirrors="true"; fi
  set_features "outbox=${outbox}" "computer_soft_deletion=${soft}" "ubuntu_pro_licensing=${pro}" \
    "repository_mirrors=${mirrors}"
}

# The outbox talks to the task handler over mutual TLS. The snaps share the
# client certificates through a content interface; here the task handler's
# self-generated client certs are linked into the outbox's certificate directory.
prepare_task_handler_certs() {
  runuser -u landscape -- /usr/local/bin/ls-task-handler certs
  ln -sfn "${DATA_DIR}/task-handler/certs/active/client" "${DATA_DIR}/outbox/grpc-certs"
  chown -h landscape:landscape "${DATA_DIR}/outbox/grpc-certs"
}

# Hash-id databases for package reporting; slow and network-dependent, so run
# in the background once services are up.
generate_hash_ids() {
  if [ -f "${DATA_DIR}/.hash_id_done" ]; then
    echo "Hash-id databases already generated."
    return 0
  fi
  if [ "${SKIP_HASH_ID_GENERATION:-false}" = "true" ]; then
    echo "Skipping hash-id database generation (SKIP_HASH_ID_GENERATION=true)"
    touch "${DATA_DIR}/.hash_id_done"
    return 0
  fi
  echo "Generating hash-id databases in background (this may take a few minutes)..."
  mkdir -p "${DATA_DIR}/hash-id-databases"
  chown landscape:landscape "${DATA_DIR}/hash-id-databases"
  (
    gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/ubuntu-archive-runtime.gpg \
      --keyserver keyserver.ubuntu.com --recv-keys \
      40976EAF437D05B5 3B4FE6ACC0B21F32 871920D1991BC93C \
      || echo "WARNING: failed to import Ubuntu archive GPG keys." >&2
    if runuser -u landscape -- python3 /opt/canonical/landscape/hash-id-databases \
      --config /opt/canonical/landscape/configs/standalone/hash-id-databases.conf; then
      touch "${DATA_DIR}/.hash_id_done"
      echo "Hash-id database generation completed successfully."
    else
      echo "WARNING: hash-id database generation failed; the weekly cron job will retry." >&2
    fi
  ) &
}

SUP_PID=""
forward_signal() {
  if [ -n "$SUP_PID" ]; then
    kill -TERM "$SUP_PID" 2>/dev/null || true
  fi
}

main() {
  restore_state
  mkdir -p /run/landscape /run/supervisor /var/log/supervisor "$DATA_DIR/debarchive" "$DATA_DIR/outbox" "$DATA_DIR/task-handler"
  chown landscape:landscape /run/landscape "$DATA_DIR/debarchive" "$DATA_DIR/outbox" "$DATA_DIR/task-handler"
  ensure_certificate
  init_postgres_cluster

  echo "Starting supervisord (PostgreSQL + RabbitMQ)..."
  supervisord -c "$SUP_CONF" &
  SUP_PID=$!
  trap forward_signal TERM INT

  wait_for "PostgreSQL" 60 pg_isready -h 127.0.0.1
  # rabbitmqctl as root needs the broker's Erlang cookie.
  for _ in $(seq 1 60); do
    [ -s /var/lib/rabbitmq/.erlang.cookie ] && break
    sleep 1
  done
  install -m 400 /var/lib/rabbitmq/.erlang.cookie /root/.erlang.cookie
  wait_for "RabbitMQ" 60 rabbitmqctl await_startup

  run_first_time_setup
  provision_rabbitmq
  fixup_vhost
  configure_features

  echo "Running database schema migration..."
  if setup-landscape-server 2>&1; then
    echo "Schema migration completed successfully."
  else
    echo "ERROR: Schema migration failed. Aborting startup." >&2
    forward_signal
    wait "$SUP_PID" || true
    exit 1
  fi
  prepare_task_handler_certs
  save_state

  echo "Starting Landscape services..."
  supctl start 'ls:*'
  generate_hash_ids

  # Block until supervisord exits (SIGTERM from docker stop, or the FATAL listener).
  local rc=0
  while kill -0 "$SUP_PID" 2>/dev/null; do
    wait "$SUP_PID" || rc=$?
  done
  echo "supervisord exited (rc=${rc}); saving configuration state."
  save_state || true
  exit "$rc"
}

main "$@"
