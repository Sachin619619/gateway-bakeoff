#!/usr/bin/env bash
# verify-headers.sh — check X-Forwarded headers and HTTPS via the gateway
# Usage: ./scripts/verify-headers.sh [http|https] [port]
#
# Examples:
#   ./scripts/verify-headers.sh http 8080     # HTTP test on port 8080
#   ./scripts/verify-headers.sh https 8443    # HTTPS test on port 8443

SCHEME="${1:-http}"
PORT="${2:-8080}"
BASE="${SCHEME}://localhost:${PORT}"

echo ""
echo "============================================"
echo " Gateway Header Verification"
echo " Target: ${BASE}"
echo "============================================"

# 1. X-Forwarded-For — client IP passed to backend
echo ""
echo "--- 1. X-Forwarded-For (client IP) ---"
curl -sk "${BASE}/get" -H "X-Forwarded-For: 203.0.113.99" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    xff = d.get('headers', {}).get('X-Forwarded-For', 'NOT PRESENT')
    print(f'  X-Forwarded-For received by backend: {xff}')
except:
    print('  ERROR: could not parse response')
"

# 2. X-Forwarded-Proto — HTTP or HTTPS
echo ""
echo "--- 2. X-Forwarded-Proto (protocol) ---"
curl -sk "${BASE}/get" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    proto = d.get('headers', {}).get('X-Forwarded-Proto', 'NOT PRESENT')
    print(f'  X-Forwarded-Proto received by backend: {proto}')
except:
    print('  ERROR: could not parse response')
"

# 3. X-Forwarded-Host — original host header
echo ""
echo "--- 3. X-Forwarded-Host (original host) ---"
curl -sk "${BASE}/get" -H "Host: localhost" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    xfh = d.get('headers', {}).get('X-Forwarded-Host', 'NOT PRESENT')
    print(f'  X-Forwarded-Host received by backend: {xfh}')
except:
    print('  ERROR: could not parse response')
"

# 4. TLS check
echo ""
echo "--- 4. TLS / HTTPS ---"
if [ "${SCHEME}" = "https" ]; then
    TLS_OUTPUT=$(curl -sk --head "${BASE}/get" | head -1)
    echo "  Response: ${TLS_OUTPUT}"
    CERT_INFO=$(echo | openssl s_client -connect localhost:${PORT} 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
    echo "  Cert info: ${CERT_INFO}"
else
    echo "  Skipped (run with 'https' scheme to test TLS)"
fi

echo ""
echo "============================================"
echo " Done"
echo "============================================"
echo ""
