# Gateway Bake-off — Roadmap

## Completed

1. ✅ kind cluster setup (single-node K8s)
2. ✅ Sample backend deployed (httpbin, 2 replicas)
3. ✅ All 5 gateways installed via Helm one at a time (NGINX, Traefik, HAProxy, Kong, Envoy)
4. ✅ Ingress routes configured per gateway
5. ✅ Load tested each gateway with k6 (50 VUs, ~90s)
6. ✅ Results recorded in scorecard (HAProxy fastest, NGINX recommended)
7. ✅ Cluster cleaned up after testing

## Next Tasks

1. 🔲 X-Forwarded headers — verify client IP and protocol passthrough (`X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host`) through each gateway
2. 🔲 HTTP → HTTPS termination — generate a mock local certificate (`mkcert`) and configure TLS on each gateway
3. 🔲 IP whitelisting and blacklisting — configure allow/deny rules per gateway (NGINX `allow/deny`, Kong IP restriction plugin, etc.)
