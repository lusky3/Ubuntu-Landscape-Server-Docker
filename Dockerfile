# syntax=docker/dockerfile:1
# Stage 1: fetch the two companion snaps from the Snap Store and unpack them with
# unsquashfs. Their binaries are plain Go executables; no snapd is needed to run
# them (see scripts/snapctl for the snapctl shim they call to read configuration).
FROM ubuntu:24.04 AS snaps
ARG TARGETARCH
ARG OUTBOX_AMD64="6JUNBMTKNtHvRrElRDJFPphgyjYNcobj_36.snap fab1031c823a3aa9d2b91d046f7d19ab0eb42182603eeeb8dd09e58763075be9e3c6dd95b382167091a8ba1b99959189"
ARG OUTBOX_ARM64="6JUNBMTKNtHvRrElRDJFPphgyjYNcobj_35.snap d94f58ff1cb739e8b7b188f1c473df4b4fdbfe68689a607bdc7ad0429de9992d1cc7cc8d3f19a214d6117b6cf544438c"
ARG DEBARCHIVE_AMD64="STBix6fNdmue37IOTOtZe8zmXv7lk4ba_406.snap 0d94c2e14f2670e846295d1c6912f3630df497c90537e9e0659407026661afb27fe96e799404462cdc4794029fd39f23"
ARG DEBARCHIVE_ARM64="STBix6fNdmue37IOTOtZe8zmXv7lk4ba_405.snap e75eb428e04c3657fa527c43ef43a84a9602f49e6cf43c53d5088281458d991c5292c110acc93052bcb629777e7ad3ce"
COPY scripts/fetch-snap /usr/local/bin/fetch-snap
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl openssl squashfs-tools && \
    rm -rf /var/lib/apt/lists/*
RUN case "${TARGETARCH:-amd64}" in \
      amd64) O="$OUTBOX_AMD64"; D="$DEBARCHIVE_AMD64" ;; \
      arm64) O="$OUTBOX_ARM64"; D="$DEBARCHIVE_ARM64" ;; \
      *) echo "unsupported architecture ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    /usr/local/bin/fetch-snap /opt/snaps/landscape-outbox ${O} && \
    /usr/local/bin/fetch-snap /opt/snaps/landscape-debarchive ${D} && \
    rm -rf /opt/snaps/landscape-debarchive/bin/temporal-server \
           /opt/snaps/landscape-debarchive/bin/temporal-sql-tool \
           /opt/snaps/landscape-debarchive/bin/temporal-setup \
           /opt/snaps/landscape-debarchive/bin/temporalshim

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Ubuntu Landscape Server"
LABEL org.opencontainers.image.description="Ubuntu Landscape Server 26.04 for systems management - self-hosted edition with web interface for managing Ubuntu systems"
LABEL org.opencontainers.image.source="https://github.com/lusky3/Ubuntu-Landscape-Server-Docker"
LABEL org.opencontainers.image.url="https://ubuntu.com/landscape"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

ENV DEBIAN_FRONTEND=noninteractive
ARG LANDSCAPE_VERSION="26.04.1-0landscape0~noble"
ARG ACME_SH_VERSION="3.1.4"

# Landscape 26.04 ships only systemd units (no /etc/init.d scripts), so the
# services are run by supervisord instead; cron replaces the maintenance jobs
# in /etc/cron.d/landscape-server. The package generates a self-signed
# cert/key at install time. It is removed in the same layer so the key is never
# shipped in the image; the entrypoint creates a certificate on first boot.
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      ca-certificates \
      software-properties-common \
      curl \
      git \
      openssl \
      gnupg \
      supervisor \
      cron \
      rsyslog && \
    apt-add-repository -y --no-update ppa:landscape/self-hosted-26.04 && \
    apt-get update && \
    PKG="landscape-server-quickstart"; \
    if [ -n "$LANDSCAPE_VERSION" ]; then PKG="${PKG}=${LANDSCAPE_VERSION}"; fi; \
    apt-get install -y --no-install-recommends "$PKG" && \
    rm -f /etc/ssl/certs/landscape_server.pem /etc/ssl/private/landscape_server.key && \
    rm -f /usr/sbin/policy-rc.d && \
    rm -rf /var/lib/apt/lists/*

# Stable RabbitMQ node name: the container hostname changes between containers.
RUN printf 'NODENAME=rabbit@localhost\nLOGS=-\nSASL_LOGS=-\n' > /etc/rabbitmq/rabbitmq-env.conf && \
    sed -i 's/^module(load="imklog"/#&/' /etc/rsyslog.conf

# Vendor a pinned acme.sh release at build time instead of curl|sh at container runtime
WORKDIR /tmp/acme.sh
RUN git clone --depth 1 --branch "${ACME_SH_VERSION}" https://github.com/acmesh-official/acme.sh.git . && \
    ./acme.sh --install --home /opt/acme.sh --no-cron --no-profile
WORKDIR /
RUN rm -rf /tmp/acme.sh

COPY --from=snaps /opt/snaps /opt/snaps
COPY scripts/snapctl /usr/local/bin/snapctl
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY --chmod=0644 landscape-outbox-cleanup.cron /etc/cron.d/landscape-outbox-cleanup
COPY scripts/ls-run scripts/ls-apache scripts/ls-fatal-listener scripts/ls-healthcheck /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/snapctl /usr/local/bin/ls-run /usr/local/bin/ls-apache \
      /usr/local/bin/ls-fatal-listener /usr/local/bin/ls-healthcheck

VOLUME ["/var/lib/postgresql", "/var/lib/landscape"]

EXPOSE 6554 443 80
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=15s --timeout=10s --start-period=180s --retries=3 \
  CMD ["/usr/local/bin/ls-healthcheck"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
