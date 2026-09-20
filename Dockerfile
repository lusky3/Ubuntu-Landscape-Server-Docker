FROM ubuntu:

LABEL org.opencontainers.image.title="Ubuntu Landscape Server"
LABEL org.opencontainers.image.description="Ubuntu Landscape Server for systems management - self-hosted edition with web interface for managing Ubuntu systems"
LABEL org.opencontainers.image.source="https://github.com/lusky3/Ubuntu-Landscape-Server-Docker"
LABEL org.opencontainers.image.url="https://ubuntu.com/landscape"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

ENV DEBIAN_FRONTEND=noninteractive
ARG LANDSCAPE_VERSION=""
ARG ACME_SH_VERSION="3.1.4"

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      ca-certificates \
      software-properties-common \
      curl \
      git \
      openssl \
      gnupg && \
    apt-add-repository -y --no-update ppa:landscape/self-hosted-24.04 || \
    (gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/landscape-ppa.gpg \
       --keyserver keyserver.ubuntu.com --recv-keys E1DD270288B4E6030699E45FA1715D88763E0DA9 && \
     echo "deb [signed-by=/etc/apt/trusted.gpg.d/landscape-ppa.gpg] http://ppa.launchpad.net/landscape/self-hosted-24.04/ubuntu noble main" > /etc/apt/sources.list.d/landscape-ubuntu-self-hosted-24-04-noble.list) && \
    apt-get update && \
    PKG="landscape-server-quickstart"; \
    if [ -n "$LANDSCAPE_VERSION" ]; then PKG="${PKG}=${LANDSCAPE_VERSION}"; fi; \
    apt-get install -y --no-install-recommends "$PKG" && \
    rm -f /usr/sbin/policy-rc.d && \
    rm -rf /var/lib/apt/lists/*

# Vendor a pinned acme.sh release at build time instead of curl|sh at container runtime
WORKDIR /tmp/acme.sh
RUN git clone --depth 1 --branch "${ACME_SH_VERSION}" https://github.com/acmesh-official/acme.sh.git . && \
    ./acme.sh --install --home /opt/acme.sh --no-cron --no-profile
WORKDIR /
RUN rm -rf /tmp/acme.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/var/lib/postgresql", "/var/lib/landscape"]

EXPOSE 6554 443 80
HEALTHCHECK --interval=15s --timeout=5s --start-period=120s --retries=20 \
  CMD ["sh", "-c", "curl -fsk https://localhost/ping || exit 1"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]