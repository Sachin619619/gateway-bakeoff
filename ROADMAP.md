# Gateway Bake-off — Roadmap

## Completed

1. ✅ kind cluster setup (single-node K8s)
2. ✅ Sample backend deployed (httpbin, 2 replicas)
3. ✅ All 5 gateways installed via Helm one at a time (NGINX, Traefik, HAProxy, Kong, Envoy)
4. ✅ Ingress routes configured per gateway
5. ✅ Load tested each gateway with k6 (50 VUs, ~90s)
6. ✅ Results recorded in scorecard (HAProxy fastest, NGINX recommended)
7. ✅ Cluster cleaned up after testing
8. ✅ X-Forwarded headers verified — `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host` tested on NGINX and Traefik
9. ✅ HTTP → HTTPS TLS termination — mkcert cert generated, stored as K8s secret, configured on NGINX and Traefik
10. ✅ Block diagrams added — X-Forwarded headers flow and TLS termination flow with full step-by-step visuals
11. ✅ OBSERVATIONS.md updated with results, diagrams, and summary table

## Next Tasks

1. 🔲 IP whitelisting and blacklisting — configure allow/deny rules per gateway (NGINX `allow/deny`, Kong IP restriction plugin, etc.)
2. 🔲 X-Forwarded headers + TLS — test HAProxy, Kong, Envoy (blocked earlier due to Docker crash)
3. 🔲 X-Forwarded-Port — add and verify port passthrough alongside existing headers
