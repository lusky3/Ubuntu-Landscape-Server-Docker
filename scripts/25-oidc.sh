#!/bin/bash
#
# Description: Configure OIDC authentication in Landscape
#

SERVICE_CONF="/etc/landscape/service.conf"

# Check if OIDC configuration is provided
if [[ -z "${OIDC_ISSUER}" ]] || [[ -z "${OIDC_CLIENT_ID}" ]] || [[ -z "${OIDC_CLIENT_SECRET}" ]]; then
    echo "25-oidc.sh: OIDC configuration not provided. Skipping OIDC setup."
    exit 0
fi

echo "25-oidc.sh: Configuring OIDC authentication..."

# Ensure service.conf exists
if [[ ! -f "${SERVICE_CONF}" ]]; then
    echo "25-oidc.sh: ${SERVICE_CONF} not found. Creating it."
    mkdir -p /etc/landscape
    cat > "${SERVICE_CONF}" << EOF
[landscape]
EOF
fi

# Check if [landscape] section exists
if ! grep -q "^\[landscape\]" "${SERVICE_CONF}"; then
    echo "25-oidc.sh: Adding [landscape] section to ${SERVICE_CONF}"
    echo "[landscape]" >> "${SERVICE_CONF}"
fi

# Add OIDC configuration
echo "25-oidc.sh: Adding OIDC settings to ${SERVICE_CONF}"
sed -i '/^\[landscape\]/a \
oidc-issuer = '"${OIDC_ISSUER}"'\
oidc-client-id = '"${OIDC_CLIENT_ID}"'\
oidc-client-secret = '"${OIDC_CLIENT_SECRET}"'' "${SERVICE_CONF}"

# Add optional logout URL if provided
if [[ -n "${OIDC_LOGOUT_URL}" ]]; then
    echo "25-oidc.sh: Adding OIDC logout URL"
    sed -i '/^oidc-client-secret/a \
oidc-logout-url = '"${OIDC_LOGOUT_URL}"'' "${SERVICE_CONF}"
fi

echo "25-oidc.sh: OIDC configuration complete."
exit 0
