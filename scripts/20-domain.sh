#!/bin/bash
#
# Description: Setup achme.sh and obtain Let'sEncrypt certificate
#
if [[ -z ${DOMAIN} ]]; then
    echo "20-domain.sh: Domain ENV is empty. Kill script."
    exit 1
fi

# Check that acme doesn't already exist or update it if it does
if [[ -f /.acme/acme.sh ]]; then
    echo "20-domain.sh: acme.sh was already found. Running update."
    acme.sh --upgrade
else
    echo "20-domain.sh: acme.sh was not found. Running install."
    # Clone acme.sh repo from github
    git clone https://github.com/acmesh-official/acme.sh.git /tmp/acme.sh && \
        cd /tmp/acme.sh && \
        # run the acme.sh installer
        ./acme.sh --install && \
        # Add a link to acme.sh in bin for ease of access
        ln -s /.acme.sh/acme.sh /usr/bin/acme.sh && \
        # Certificates will be placed in /etc/ssl/certs
        mkdir -p /etc/ssl/certs && \
        mkdir -p /etc/ssl/private
fi

if [ ! "$(command -v acme.sh)" ]; then
    echo "20-domain.sh: acme.sh did not install properly. We will be unable to request a certificate."
    echo "20-domain.sh: This won't cause a script failure, but certificate for landscape will likely be self-signed."
    echo "20-domain.sh: End script."
    exit 0
fi

# Check if ECDSA is wanted (Default = true)
if [[ "${ECDSA}" -eq "true" ]]; then
    echo "20-domain.sh: ECDSA certificate is wanted."
    export ECDSA=" --keylength ec-256 --ecc"
else
    echo "20-domain.sh: RSA certificate is wanted."
    export ECDSA=""
fi

# We don't want to waste our time if the certificates already exist
if [[ -f /.acme.sh/$DOMAIN/${DOMAIN}.cer ]] || [[ -f /.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]]; then
    echo "20-domain.sh: Certificate for $DOMAIN appears to already exist, so we will only try to install it."
    mkdir -p /etc/ssl/certs && \
        mkdir -p /etc/ssl/private
    acme.sh --install-cert -d $DOMAIN${ECDSA:19:25} \
        --cert-file      /etc/ssl/certs/landscape_server.pem  \
        --key-file       /etc/ssl/private/landscape_server.key  \
        --fullchain-file /etc/ssl/certs/landscape_server_ca.crt \
        --reloadcmd     "service apache2 force-reload"
    exit 0
else
    echo "20-domain.sh: Certificate for $DOMAIN does not appear to exist, so we will try to request it."
    # Cloudflare
    if [[ -n "${CF_Token}" && -n "${CF_Account_ID}" ]] || [[ -n "${CF_Key}" && -n "${CF_Email}" ]]; then
        DNS_METHOD="--dns dns_cf"
    # AWS Route53
    elif [[ -n "${AWS_ACCESS_KEY_ID}" && -n "${AWS_SECRET_ACCESS_KEY}" ]]; then
        DNS_METHOD="--dns dns_aws"
    # FreeDNS
    elif [[ -n "${FREEDNS_User}" && -n "${FREEDNS_Password}" ]]; then
        DNS_METHOD="--dns dns_freedns"
    # Fallback to Apache
    else
        echo "20-domain.sh: DNS verification ENV values not found. Fallback to webroot (apache) method."
        DNS_METHOD="--apache"
    fi

    # Request the sertificate from Let'sEncrypt
    echo "20-domain.sh: Attempting to request certificate..."
    acme.sh --issue $DNS_METHOD -d $DOMAIN${ECDSA:0:19}
    # Install the certificate
    if [[ -f /.acme.sh/$DOMAIN/${DOMAIN}.cer ]] || [[ -d /.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer ]]; then
        echo "20-domain.sh: Certificate for $DOMAIN was found. Attempting to install to Apache..."
        acme.sh --install-cert -d $DOMAIN${ECDSA:19:25} \
            --cert-file      /etc/ssl/certs/landscape_server.pem  \
            --key-file       /etc/ssl/private/landscape_server.key  \
            --fullchain-file /etc/ssl/certs/landscape_server_ca.crt \
            --reloadcmd     "service apache2 force-reload"
    else   
        echo "20-domain.sh: Certificate for $DOMAIN was Not Found."
        echo "20-domain.sh: Certificate request may have failed. Run acme.sh manually."
        echo "20-domain.sh: This won't cause a script failure, but certificate for landscape will likely be self-signed."
        echo "20-domain.sh: End script."
        exit 0
    fi
fi
echo "20-domain.sh: Certificate requested and installed to Apache. Ending script."
exit 0