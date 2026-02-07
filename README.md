# Ubuntu Landscape Server (for Docker)

All-in-one Docker container for Ubuntu Landscape Server with automatic SSL certificate generation.

## Prerequisites

- Docker and Docker Compose
- Ubuntu Pro token (get free token at https://ubuntu.com/pro)

## Quick Start

1. Copy the environment template:
```bash
cp .env.example .env.local
```

2. Edit `.env.local` and add your Ubuntu Pro token:
```
UBUNTU_PRO_TOKEN=your_actual_token_here
```

3. Build and start:
```bash
docker compose up -d
```

4. Access Landscape at https://localhost:8443

## SSL Certificates

The container automatically generates SSL certificates on first boot:

**Self-Signed (Default)**
- Automatically generated if no DNS provider is configured
- Valid for 1 year
- Browser will show security warning (accept to proceed)

**Let's Encrypt with DNS Authorization (Optional)**
Add to `.env.local`:

Cloudflare:
```
LANDSCAPE_FQDN=landscape.example.com
ACME_DNS_PROVIDER=cf
ACME_CF_Token=your_cloudflare_api_token
```

Route53:
```
LANDSCAPE_FQDN=landscape.example.com
ACME_DNS_PROVIDER=aws
ACME_AWS_ACCESS_KEY_ID=your_key
ACME_AWS_SECRET_ACCESS_KEY=your_secret
```

GoDaddy:
```
LANDSCAPE_FQDN=landscape.example.com
ACME_DNS_PROVIDER=gd
ACME_GD_Key=your_key
ACME_GD_Secret=your_secret
```

See [acme.sh DNS API docs](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) for all supported providers.

## Ports

- `8080`: HTTP (redirects to HTTPS)
- `8443`: HTTPS (main access)

## First Boot

First startup takes 2-3 minutes:
1. Generates SSL certificate
2. Attaches Ubuntu Pro subscription
3. Installs Landscape Server
4. Configures PostgreSQL and RabbitMQ
5. Initializes databases

## Create Admin Account

On first access, you'll see a signup form to create the admin account.

## Logs

```bash
docker logs -f landscape-server
```
