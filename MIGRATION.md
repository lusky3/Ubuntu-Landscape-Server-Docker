# Client Dockerfiles Migration

## Changes Made

### Directory Structure
- Created `clients/` directory
- Moved all client Dockerfiles to `clients/` folder
- Renamed `Dockerfile.client` → `Dockerfile.client.24.04`

### Files Updated

#### Docker Compose
- **compose.yml**: Updated client build path to `clients/Dockerfile.client.24.04`

#### GitHub Workflows
- **.github/workflows/build.yml**: Updated client Dockerfile path
- **.github/workflows/ci.yml**: Updated client Dockerfile path and hadolint check
- **.github/workflows/quality.yml**: Added matrix build to lint all client Dockerfiles
- **.github/workflows/update-base-image.yml**: Updated sed command to target new path
- **.github/workflows/build-clients.yml**: NEW - Builds and publishes all client versions
- **.github/workflows/test-clients.yml**: NEW - Tests all client versions in CI

#### Documentation
- **README.md**: Added section documenting all available Ubuntu versions

## Available Client Images

After these changes, the following images will be built and published:

### GitHub Container Registry
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:12.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:14.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:16.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:18.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:24.04`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:25.10`
- `ghcr.io/lusky3/ubuntu-landscape-server-docker-client:latest` (points to 24.04)

### Docker Hub
- `<username>/landscape-server-client:12.04`
- `<username>/landscape-server-client:14.04`
- `<username>/landscape-server-client:16.04`
- `<username>/landscape-server-client:18.04`
- `<username>/landscape-server-client:24.04`
- `<username>/landscape-server-client:25.10`
- `<username>/landscape-server-client:latest` (points to 24.04)

## Workflow Triggers

### build-clients.yml
Triggers on:
- Push to main (when `clients/**` or `client-entrypoint.sh` changes)
- Manual workflow dispatch

### test-clients.yml
Triggers on:
- Pull requests (when `clients/**` or `client-entrypoint.sh` changes)
- Push to main (when `clients/**` or `client-entrypoint.sh` changes)
- Manual workflow dispatch

## Testing Locally

To test a specific client version:
```bash
docker build -f clients/Dockerfile.client.18.04 -t landscape-client:18.04 .
docker run -d landscape-client:18.04
```

To test all versions, use the test script (if available):
```bash
./test-dockerfiles.sh
```
