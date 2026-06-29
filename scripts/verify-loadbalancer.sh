#!/usr/bin/env bash
# Verify a gateway service exposed as type LoadBalancer.
#
# Usage:
#   ./scripts/verify-loadbalancer.sh <namespace> <service-name> [http-port] [https-port]
#
# Example:
#   ./scripts/verify-loadbalancer.sh ingress-nginx nginx-ingress-nginx-controller

set -euo pipefail

NAMESPACE="${1:-}"
SERVICE="${2:-}"
HTTP_PORT="${3:-80}"
HTTPS_PORT="${4:-443}"

if [ -z "${NAMESPACE}" ] || [ -z "${SERVICE}" ]; then
  echo "Usage: $0 <namespace> <service-name> [http-port] [https-port]" >&2
  exit 1
fi

LB_IP="$(kubectl -n "${NAMESPACE}" get svc "${SERVICE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
if [ -z "${LB_IP}" ]; then
  echo "LoadBalancer IP is not assigned yet for ${NAMESPACE}/${SERVICE}." >&2
  echo "Run: kubectl -n ${NAMESPACE} get svc ${SERVICE}" >&2
  exit 1
fi

echo ""
echo "============================================"
echo " Gateway LoadBalancer Verification"
echo " Service: ${NAMESPACE}/${SERVICE}"
echo " IP:      ${LB_IP}"
echo "============================================"

echo ""
echo "--- 1. HTTP route ---"
HTTP_BODY="$(curl --max-time 10 -fsS "http://${LB_IP}:${HTTP_PORT}/get")"
printf '%s' "${HTTP_BODY}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('  HTTP status: reachable')
    print('  Host seen by backend:', d.get('headers', {}).get('Host', 'NOT PRESENT'))
except Exception as exc:
    print('  ERROR: could not parse HTTP response:', exc)
"

echo ""
echo "--- 2. HTTPS route ---"
HTTPS_BODY="$(curl --max-time 10 -fskS "https://${LB_IP}:${HTTPS_PORT}/get")"
printf '%s' "${HTTPS_BODY}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('  HTTPS status: reachable')
    print('  X-Forwarded-Proto:', d.get('headers', {}).get('X-Forwarded-Proto', 'NOT PRESENT'))
except Exception as exc:
    print('  ERROR: could not parse HTTPS response:', exc)
"

echo ""
echo "--- 3. Service summary ---"
kubectl -n "${NAMESPACE}" get svc "${SERVICE}" -o wide

echo ""
echo "Load test target:"
echo "  BASE=http://${LB_IP}:${HTTP_PORT} k6 run k6-test.js"
echo ""
