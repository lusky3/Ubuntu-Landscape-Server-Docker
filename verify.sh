#!/bin/bash
set -uo pipefail

echo "=== Landscape Server & Client Status ==="
echo ""

FAILURES=0

echo "Server Certificate SAN:"
if ! docker exec landscape-client openssl s_client -connect landscape-server:443 </dev/null 2>&1 | openssl x509 -noout -text | grep -A3 "Subject Alternative Name"; then
  echo "FAILED to read certificate SAN"
  FAILURES=$((FAILURES + 1))
fi
echo ""

echo "Client Registration Status:"
REGISTERED=$(docker exec landscape-client landscape-config --is-registered 2>&1)
echo "$REGISTERED"
if ! echo "$REGISTERED" | grep -q "True"; then
  echo "FAILED: client is not registered"
  FAILURES=$((FAILURES + 1))
fi
echo ""

echo "Pending Computers in Database:"
if ! docker exec landscape-server su postgres -c "psql landscape-standalone-main -c 'SELECT id, hostname, title FROM pending_computer;'"; then
  FAILURES=$((FAILURES + 1))
fi
echo ""

echo "Accepted Computers in Database:"
if ! docker exec landscape-server su postgres -c "psql landscape-standalone-main -c 'SELECT id, hostname, title FROM computer;'"; then
  FAILURES=$((FAILURES + 1))
fi
echo ""

if [ "$FAILURES" -eq 0 ]; then
  echo "✅ SUCCESS: Client is enrolled and waiting for approval in Landscape dashboard"
  echo "   Access dashboard at: https://localhost"
  echo "   Default admin email (unless ADMIN_EMAIL was overridden): admin@landscape.local"
  echo "   Password: docker exec landscape-server cat /var/lib/landscape/admin-credentials.txt"
  exit 0
else
  echo "❌ FAILED: $FAILURES check(s) failed - see output above"
  exit 1
fi
