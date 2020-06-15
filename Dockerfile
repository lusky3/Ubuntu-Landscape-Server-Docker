# Use phusion/baseimage as base image.
FROM phusion/baseimage:bionic-1.0.0

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

RUN apt-get update && \
    apt-get upgrade -y -o Dpkg::Options::="--force-confold" && \
    apt-get install -y locales software-properties-common git && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    add-apt-repository -y --update ppa:landscape/19.10 && \
    apt-get install -y landscape-server-quickstart && \
    apt-get -y autoremove && \
    mkdir -p /etc/my_init.d

COPY scripts/20-domain.sh /etc/my_init.d/20-domain.sh

ENV LANG=en_US.utf8 \
CF_Email="" \
CF_Key="" \
CF_Account_ID="" \
CF_Token="" \
AWS_ACCESS_KEY_ID="" \
AWS_SECRET_ACCESS_KEY="" \
FREEDNS_User="" \
FREEDNS_Password="" \
ECDSA=true \
DOMAIN=""

# Final processes
RUN chmod +x /etc/my_init.d/domain.sh && \
# Clean up APT when done.
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose the web server (apache) for Landscape
EXPOSE 80 443

# We want to refrain from requesting certificates unnecessarily
VOLUME [ "/root/.acme" ]