# Use phusion/baseimage as base image.
FROM phusion/baseimage:bionic-1.0.0

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get upgrade -y -o Dpkg::Options::="--force-confold" && \
    apt-get install -y locales software-properties-common git postfix && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    add-apt-repository -y --update ppa:landscape/19.10 && \
    apt-get install -y landscape-server-quickstart && \
    apt-get install -y syslog-ng && \
    apt-get -y autoremove && \
    mkdir -p /etc/my_init.d

COPY scripts/* /etc/my_init.d/

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
DOMAIN="landscape.host.local" \
ADMIN_EMAIL="" \
USE_SMTP_RELAY=false \
SMTP_RELAY_HOST="" \
SMTP_RELAY_USERNAME="Username" \
SMTP_RELAY_PASSWORD="Password" \
SMTP_RELAY_PORT="2525"

# Final processes
RUN rm /etc/init.d/syslog-ng && \
    mv /etc/init.d/apache2 /etc/my_init.d/ && \
    mv /etc/init.d/apache-htcacheclean /etc/my_init.d/ && \
    mv /etc/init.d/rabbitmq-server /etc/my_init.d/ && \
    mv /etc/init.d/postfix /etc/my_init.d/ && \
    chmod +x /etc/my_init.d/* && \
    unset DEBIAN_FRONTEND && \
# Clean up APT when done.
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose the web server (apache) for Landscape
EXPOSE 80 443

# We want to refrain from requesting certificates unnecessarily
VOLUME [ "/.acme.sh" ]