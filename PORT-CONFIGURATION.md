# Ubuntu Landscape Server - Port Configuration

## Standard Configuration (Recommended)

The default `compose.yml` uses standard ports:
- HTTP: `8080:80`
- HTTPS: `443:443`

Access at: https://localhost

## Custom Port Configuration

If you need to use a non-standard external port (e.g., `8443`), you'll need to:

1. Update `compose.yml`:
```yaml
ports:
  - "8080:80"
  - "8443:443"
environment:
  - LANDSCAPE_FQDN=localhost:8443
```

2. The application will still have CSP and redirect issues because Landscape expects standard ports.

**Recommendation:** Use standard port `443:443` or run with `--net=host` if you need custom ports.

## Why Standard Ports?

Landscape's Apache configuration and CSP headers assume standard HTTPS (443). Using non-standard ports causes:
- Content Security Policy violations
- Incorrect redirects (drops port from URLs)
- Session/cookie issues

## Alternative: Host Network Mode

```yaml
services:
  landscape:
    network_mode: host
    # No ports mapping needed
```

Then configure Apache inside the container to listen on your desired port.
