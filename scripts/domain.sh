#!/bin/bash
#
# Description: Setup achme.sh and obtain Let'sEncrypt certificate
#
if [[ -z ${DOMAIN} ]]; then
    echo "Domain ENV is empty. Kill script."
    exit 1
fi
# Clone acme.sh repo from github
git clone https://github.com/acmesh-official/acme.sh.git /tmp/achme.sh && \
    cd /tmp/acme.sh && \
    # run the acme.sh installer
    ./acme.sh --install && \
    # Add a link to acme.sh in bin for ease of access
    ln -s /.acme.sh/acme.sh /usr/bin/acme.sh && \
    # Certificates will be placed in /etc/ssl/certs
    mkdir -p /etc/ssl/certs && \
    mkdir -p /etc/ssl/private
# Cloudflare
if [[ -n "${CF_Token}" && -n "${CF_Account_ID}" ]] || [[ -n "${CF_Key}" && -n "${CF_Email}" ]; then
    DNS_METHOD="--dns dns_cf"
# AWS Route53
elif [ -n "${AWS_ACCESS_KEY_ID}" && -n "${AWS_SECRET_ACCESS_KEY}" ]; then
    DNS_METHOD="--dns dns_aws"
# FreeDNS
elif [ -n "${FREEDNS_User}" && -n "${FREEDNS_Password}" ]; then
    DNS_METHOD="--dns dns_freedns"
# Fallback to Apache
else
    DNS_METHOD="--apache"
fi
# Check if ECDSA is wanted (Default = true)
if [[ "${ECDSA}" -eq "true" ]]; then
    ECDSA=" --ecc ec-256"
else
    ECDSA=""
fi
# Request the sertificate from Let'sEncrypt
acme.sh --issue $DNS_METHOD -d $DOMAIN$ECDSA
# Install the certificate
acme.sh --install-cert -d $DOMAIN${ECDSA:0:7} \
--cert-file      /etc/ssl/certs/landscape_server.pem  \
--key-file       /etc/ssl/private/landscape_server.key  \
--fullchain-file /etc/ssl/certs/landscape_server_ca.crt \
--reloadcmd     "service apache2 force-reload"

exit 0