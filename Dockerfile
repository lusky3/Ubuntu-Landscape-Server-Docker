FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      ca-certificates \
      software-properties-common \
      curl \
      openssl && \
    apt-add-repository -y ppa:landscape/self-hosted-24.04 && \
    apt-get install -y --no-install-recommends landscape-server-quickstart && \
    rm -f /usr/sbin/policy-rc.d && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 6554 443 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
