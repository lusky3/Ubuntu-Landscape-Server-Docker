FROM ubuntu:

LABEL org.opencontainers.image.title="Ubuntu Landscape Server"
LABEL org.opencontainers.image.description="Ubuntu Landscape Server for systems management - self-hosted edition with web interface for managing Ubuntu systems"
LABEL org.opencontainers.image.source="https://github.com/lusky3/Ubuntu-Landscape-Server-Docker"
LABEL org.opencontainers.image.url="https://ubuntu.com/landscape"
LABEL org.opencontainers.image.licenses="AGPL-3.0"

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      ca-certificates \
      software-properties-common \
      curl \
      openssl \
      gnupg && \
    apt-add-repository -y ppa:landscape/self-hosted-24.04 && \
    apt-get install -y --no-install-recommends landscape-server-quickstart && \
    rm -f /usr/sbin/policy-rc.d && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/var/lib/postgresql", "/var/lib/landscape"]

EXPOSE 6554 443 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
