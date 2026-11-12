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
- Valid for 10 years
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

How it works:
- Credentials are handed to [acme.sh](https://github.com/acmesh-official/acme.sh) with the `ACME_` prefix
  removed (`ACME_CF_Token` becomes `CF_Token`), so use the variable names from the acme.sh DNS API docs,
  each prefixed with `ACME_`.
- `ACME_SERVER` selects the certificate authority (default `letsencrypt`). Set it to `letsencrypt_test`
  to try your setup against Let's Encrypt staging first; staging certificates are not trusted by browsers,
  but they don't count against production rate limits.
- If issuance fails, the error is logged and the container falls back to a self-signed certificate.
- The certificate is requested when a container is first created. It is stored with acme.sh's account
  data in the `landscape` volume, so restarts and recreated containers reuse it without a new issuance.
- Renewal is automatic: a daily cron job runs `acme.sh --cron`, which renews certificates that are within
  30 days of expiry (the DNS credentials are kept in acme.sh's account config), reinstalls the files and
  reloads Apache without a restart. The log is `/var/log/landscape/acme-renew.log`.

## Ports

- `8080`: HTTP (redirects to HTTPS)
- `443`: HTTPS (main access)

If you publish 443 on a different host port (e.g. `-p 8443:443`), set
`LANDSCAPE_PUBLIC_PORT=8443` (default `443`). Without it the classic UI returns
HTTP 500 and the HTTP-to-HTTPS redirect points at the wrong port, because the
generated Apache vhost hardcodes `:443` in its virtual-host rewrite rules. The
entrypoint rewrites those rules on every start. Leave it at `443` behind a
reverse proxy that serves HTTPS on 443.

## First Boot

First startup takes 2-3 minutes:
1. Generates SSL certificate
2. Installs Landscape Server
3. Configures PostgreSQL and RabbitMQ
4. Initializes databases

## Landscape 26.04: how it runs without systemd

Landscape 26.04 removed its SysV init scripts and is managed only through systemd
units, so the container runs everything under `supervisord` (`supervisord.conf`):
PostgreSQL, RabbitMQ, rsyslog, Apache, cron (the maintenance jobs from
`/etc/cron.d/landscape-server`) and every service in `landscape-server.target`
(api, appserver, async-frontend, job-handler, msgserver, package-upload,
pingserver, package-search, hostagent-consumer, hostagent-messenger,
secrets-service). The three companion snaps Canonical ships only as snaps
(`landscape-outbox`, `landscape-task-handler`, `landscape-debarchive`) are
unpacked at build time (checksum-pinned) and run directly, with
`scripts/snapctl` standing in for snapd's `snapctl`. Outbox, computer soft
deletion and repository mirrors are enabled by default; set
`LANDSCAPE_ENABLE_OUTBOX`, `LANDSCAPE_ENABLE_SOFT_DELETION`,
`LANDSCAPE_ENABLE_REPOSITORY_MIRRORS` or `LANDSCAPE_ENABLE_PRO_LICENSING` to
`false` to turn one off.

If any program exhausts its start retries (supervisord `FATAL`), the container
exits; the healthcheck (`ls-healthcheck`) reports unhealthy whenever any
program is not `RUNNING` or `/ping` fails. Give the container time to stop
cleanly (`stop_grace_period: 60s` in `compose.yml`).

Configuration generated at first boot (service.conf, Apache vhost, certificates)
is archived into the `/var/lib/landscape` volume and restored on a new container.

Licensing: computers can only be accepted if the account has licenses. Mount a
Landscape license at `/etc/landscape/license.txt`, or rely on Ubuntu Pro
licensing (enabled by default here; unlicensed computers are accepted with a
reduced feature set).

## Upgrading from 24.04

The 26.04 image can run on the volumes of a 24.04 image (`/var/lib/postgresql`
and `/var/lib/landscape`): stop the old container gracefully (`docker stop`),
then start the new image with the same two volumes. On the first boot it
notices data without a saved configuration archive and, in place:

- runs `landscape-quickstart` again to regenerate `service.conf`, the Apache
  vhost and the RabbitMQ settings (the 24.04 image kept them only in the
  container, not on a volume);
- gives the database roles new passwords and records them in `service.conf`;
- migrates the schema to 26.04 (this cannot be rolled back, so back up both
  volumes first);
- renames the default admin `admin@landscape.local` to `ADMIN_EMAIL` (default
  `admin@landscape.example`), because the 26.04 login rejects `.local`
  addresses. The password is unchanged.

Manual steps:

- **Admin login:** use the new email. If you chose a custom `.local` admin
  address, change it yourself.
- **Clients that pin the server certificate** (`ssl_public_key`, as the test
  client in this repo does) will fail with "server certificate verification
  failed", because the self-signed certificate lived in the old container and
  a new one is generated. Either copy the old certificate and key out before
  removing the old container (`docker cp <old>:/etc/ssl/certs/landscape_server.pem .`
  and `docker cp <old>:/etc/ssl/private/landscape_server.key .`) and mount them
  at the same paths in the new one, or re-fetch the certificate on each client.
  Clients that trust a CA-issued (ACME) certificate are not affected.

## Create Admin Account

On first access, you'll see a signup form to create the admin account.

Alternatively, a default admin account is created automatically on first boot:
- Email: `admin@landscape.example` (override with the `ADMIN_EMAIL` env var)
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
- **Auto-merge**: PRs with the `auto-merge` label are merged automatically once the required checks pass.
- **Required checks**: the `Main` ruleset blocks merging into `main` until `test-server`, `test-client`, `shellcheck`,
  `yaml-lint`, `hadolint (Dockerfile)` and `hadolint (clients/Dockerfile.client)` have passed. If you rename or remove
  one of those jobs, update the ruleset as well, otherwise merges wait forever for a check that never reports.
- **Automation identity**: the Landscape/base-image update PRs are opened, and auto-merged PRs are merged, by the
  [LuskTech-Neko](https://github.com/apps/lusktech-neko) GitHub App. GitHub does not run workflows for PRs or pushes
  made with the default `GITHUB_TOKEN`, so the app token is what makes CI and image publishing run on them. It needs
  the `RELEASE_CLIENT_ID` repository variable and the `RELEASE_APP_PRIVATE_KEY` secret, and the app must be installed
  on this repository with write access to contents and pull requests.

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
