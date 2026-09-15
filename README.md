# Ubuntu Landscape Server (for Docker)

[![CI](https://github.com/lusky3/Ubuntu-Landscape-Server-Docker/actions/workflows/ci.yml/badge.svg)](https://github.com/lusky3/Ubuntu-Landscape-Server-Docker/actions/workflows/ci.yml)
[![Build](https://github.com/lusky3/Ubuntu-Landscape-Server-Docker/actions/workflows/build.yml/badge.svg)](https://github.com/lusky3/Ubuntu-Landscape-Server-Docker/actions/workflows/build.yml)
[![Latest Release](https://img.shields.io/github/v/release/lusky3/Ubuntu-Landscape-Server-Docker)](https://github.com/lusky3/Ubuntu-Landscape-Server-Docker/releases/latest)

All-in-one Docker container for Ubuntu Landscape Server with automatic SSL certificate generation, automated updates, and comprehensive CI/CD.

## Quick Start

### Using Pre-built Images (Recommended)

Pull from Docker Hub:
```bash
docker pull <your-dockerhub-username>/landscape-server:latest
docker pull <your-dockerhub-username>/landscape-server-client:latest
```

Or use GitHub Container Registry:
```bash
docker pull ghcr.io/lusky3/ubuntu-landscape-server-docker/landscape:latest
docker pull ghcr.io/lusky3/ubuntu-landscape-server-docker/landscape-client:latest
```

### Building Locally

1. Copy the environment template (optional - only needed for Let's Encrypt DNS
   authorization, see below):
```bash
cp .env.example .env.local
```

2. Build and start:
```bash
docker compose up -d
```

3. Access Landscape at https://localhost

## Prerequisites

- Docker and Docker Compose

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
- `443`: HTTPS (main access)

## First Boot

First startup takes 2-3 minutes:
1. Generates SSL certificate
2. Installs Landscape Server
3. Configures PostgreSQL and RabbitMQ
4. Initializes databases

## Create Admin Account

On first access, you'll see a signup form to create the admin account.

Alternatively, a default admin account is created automatically on first boot:
- Email: `admin@landscape.local` (override with the `ADMIN_EMAIL` env var)
- Password: a randomly generated password, written to
  `/var/lib/landscape/admin-credentials.txt` inside the container
  (root-readable only). Retrieve it with:
  ```bash
  docker exec landscape-server cat /var/lib/landscape/admin-credentials.txt
  ```
  Or set your own via the `ADMIN_PASSWORD` env var before first boot.

## Optional: Test Client

To start a test Ubuntu client that auto-enrolls:

```bash
docker compose --profile with-client up -d
```

The client will automatically register with the Landscape server. View it in the dashboard under "Computers".

### Multiple Ubuntu Versions

Client images are available for multiple Ubuntu versions:
- `12.04` (Precise) - EOL
- `14.04` (Trusty) - EOL
- `16.04` (Xenial) - EOL
- `18.04` (Bionic) - EOL
- `20.04` (Focal) - LTS
- `22.04` (Jammy) - LTS
- `24.04` (Noble) - LTS
- `25.10` (Plucky)

To use a specific version, modify `compose.yml`:
```yaml
landscape-client:
  build:
    context: .
    dockerfile: clients/Dockerfile.client
    args:
      UBUNTU_VERSION: "18.04"  # Change version here
```

Or pull pre-built images:
```bash
docker pull ghcr.io/lusky3/ubuntu-landscape-server-docker-client:18.04
docker pull <your-dockerhub-username>/landscape-server-client:18.04
```

#### Available Pre-built Images

**GitHub Container Registry:**
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:12.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:14.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:16.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:18.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:20.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:22.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:24.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:25.10`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:latest` (24.04)

**Docker Hub:**
- `<your-dockerhub-username>/landscape-server-client:12.04`
- `<your-dockerhub-username>/landscape-server-client:14.04`
- `<your-dockerhub-username>/landscape-server-client:16.04`
- `<your-dockerhub-username>/landscape-server-client:18.04`
- `<your-dockerhub-username>/landscape-server-client:20.04`
- `<your-dockerhub-username>/landscape-server-client:22.04`
- `<your-dockerhub-username>/landscape-server-client:24.04`
- `<your-dockerhub-username>/landscape-server-client:25.10`
- `<your-dockerhub-username>/landscape-server-client:latest` (24.04)

To customize the client:
```bash
# Edit compose.yml landscape-client environment:
LANDSCAPE_URL=https://landscape-server
ACCOUNT_NAME=standalone
COMPUTER_TITLE=My Test Client
REGISTRATION_KEY=optional_key  # If required by account
SCRIPT_USERS=ALL  # Opt-in only: allows the server to run scripts on this client
                  # as any user. Omitted (safe) by default.
```

## Logs

```bash
docker logs -f landscape-server
```

## CI/CD Pipeline

This project includes a comprehensive automated CI/CD pipeline:

### Automated Testing
- **Linting**: ShellCheck, Hadolint, YAML validation
- **Build Tests**: Multi-architecture Docker builds with caching
- **Integration Tests**: Server health checks, client registration, database validation
- **Security Scanning**: Trivy vulnerability scanner

### Automated Updates
- **Landscape Version Tracking**: Weekly checks for new Landscape releases from Ubuntu PPA
- **Base Image Updates**: Weekly checks for Ubuntu base image updates
- **Dependabot**: Automatic dependency updates for GitHub Actions and Docker
- **Auto-merge**: PRs with `auto-merge` label will auto-merge after CI passes (requires manual approval for workflow changes due to GitHub security restrictions)

### Publishing
Images are automatically built and published to both registries on every push to main:
- **Docker Hub**: `<your-dockerhub-username>/landscape-server:main` and `<your-dockerhub-username>/landscape-server-client:main`
- **GitHub Container Registry**: `ghcr.io/lusky3/ubuntu-landscape-server-docker/landscape:main`

### Discord Notifications
Automated notifications for:
- Pull request events (opened, merged, closed)
- Issue events (opened, closed)
- New releases published
- Workflow failures
- Successful deployments

To enable Discord notifications, add `DISCORD_WEBOOK` secret to your repository with your Discord webhook URL.

### Automated Releases
- Semantic versioning with automated changelog generation
- Release notes include all commits since last release
- Triggered manually via GitHub Actions

## Development

### Running Tests Locally

```bash
# Run full CI suite
docker compose up -d
docker compose --profile with-client up -d

# Check server health
curl -k https://localhost

# Check client registration
docker exec landscape-client landscape-config --is-registered
```

### Version Tracking

Current Landscape version is tracked in `.landscape-version` file. The automated update workflow checks for new versions weekly and creates PRs automatically.
