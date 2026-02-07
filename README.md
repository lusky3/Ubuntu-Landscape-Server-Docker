# Ubuntu Landscape Server (for Docker)
  
An all-in-one Ubuntu Landscape Server for Docker.
  
Designed for small to medium deployments. For enterprise deployments, consider the [Juju deployment method](https://documentation.ubuntu.com/landscape/en/landscape-install-juju).

## Features

- Ubuntu 24.04 LTS base
- Landscape Server 24.04 LTS
- Automatic Let's Encrypt SSL certificates via acme.sh
- DNS validation support (Cloudflare, AWS Route53, FreeDNS)
- Webroot validation fallback
- Integrated PostgreSQL and RabbitMQ
- Email notifications via Postfix

## Quick Start

1. Clone the repository:
```bash
git clone git@github.com:lusky3/Ubuntu-Landscape-Server--Docker-.git
cd Ubuntu-Landscape-Server--Docker-
git checkout dev
```

2. Create your environment file:
```bash
cp .env.example .env
# Edit .env with your settings
nano .env
```

3. Build and run:
```bash
docker-compose up -d
```

4. Access Landscape at `https://your-domain.com`

## Environment Variables

### Required

- `DOMAIN` - FQDN for your Landscape server (e.g., landscape.example.com)
- `ADMIN_EMAIL` - Email for system alerts

### SSL Certificate (acme.sh)

Choose ONE DNS validation method, or leave empty for webroot validation:

**Cloudflare (Global API - less secure):**
- `CF_Email` - Cloudflare account email
- `CF_Key` - Global API key

**Cloudflare (Token - more secure, recommended):**
- `CF_Account_ID` - Cloudflare account ID
- `CF_Token` - API token with DNS edit permissions

**AWS Route53:**
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key

**FreeDNS:**
- `FREEDNS_User` - FreeDNS username
- `FREEDNS_Password` - FreeDNS password

**Certificate Type:**
- `ECDSA` - Use ECDSA certificates (true) or RSA (false). Default: true

### Email (Postfix)

- `USE_SMTP_RELAY` - Use SMTP relay (true/false). Default: false
- `SMTP_RELAY_HOST` - SMTP server hostname
- `SMTP_RELAY_USERNAME` - SMTP username
- `SMTP_RELAY_PASSWORD` - SMTP password
- `SMTP_RELAY_PORT` - SMTP port. Default: 2525

## Volumes

- `acme-data` - Let's Encrypt certificates and acme.sh data
- `landscape-data` - Landscape application data
- `postgres-data` - PostgreSQL database

## Ports

- `80` - HTTP (redirects to HTTPS)
- `443` - HTTPS

## Notes

- First startup may take several minutes while Landscape initializes
- SSL certificates are automatically renewed by acme.sh
- For production use, ensure proper DNS records point to your server
- Landscape requires Ubuntu Pro for full functionality

## Troubleshooting

View logs:
```bash
docker-compose logs -f landscape
```

Restart services:
```bash
docker-compose restart
```

Rebuild after changes:
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## License

This is an unofficial Docker implementation. Ubuntu Landscape is a Canonical product.
