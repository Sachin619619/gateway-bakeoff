# Gateway Bake-off — Results & Observations

Tested on: local kind cluster (single-node), macOS Apple Silicon
Gateways: NGINX Ingress, Traefik, HAProxy, Kong, Envoy
Backend: httpbin (2 replicas)
Load test: k6, 50 virtual users, ~90 seconds

---

## 1. Load Test

| Rank | Gateway | Req/s | p50 | p95 | Errors |
|------|---------|-------|-----|-----|--------|
| 1 | HAProxy | 6,665 | 5.5 ms | 12.2 ms | 0% |
| 2 | Traefik | 5,923 | 6.3 ms | 13.4 ms | 0% |
| 3 | NGINX | 5,326 | 6.7 ms | 15.9 ms | 0% |
| 4 | Kong | 5,123 | 7.0 ms | 17.1 ms | 0% |
| 5 | Envoy | 4,789 | 7.2 ms | 18.4 ms | 0% |

- All 5 gateways returned 0% errors — all are stable
- HAProxy is the fastest in raw throughput
- Performance spread is small — all are close
- Recommended: NGINX (maturity, ecosystem, built-in WAF path)

---

## 2. X-Forwarded Headers

What we tested: sent a request and checked if the backend received
the correct client IP, protocol, and host through each gateway.

| Gateway | X-Forwarded-For | X-Forwarded-Proto | X-Forwarded-Host | Config needed |
|---------|----------------|-------------------|------------------|---------------|
| NGINX | 203.0.113.99, 127.0.0.1 | https | localhost | Yes — 2 extra flags |
| Traefik | 127.0.0.1 | https | localhost | No — works by default |
| HAProxy | not tested | not tested | not tested | — |
| Kong | not tested | not tested | not tested | — |
| Envoy | not tested | not tested | not tested | — |

Key findings:
- NGINX needs use-forwarded-headers=true and compute-full-forwarded-for=true flags at install
- NGINX appends its own gateway IP to X-Forwarded-For (full hop chain)
- Traefik injects all 3 headers automatically with zero config
- Both correctly passed X-Forwarded-Proto as https after TLS termination

---

## 3. TLS Termination (HTTPS)

What we tested: generated a local cert with mkcert, stored it as a
Kubernetes TLS secret, and configured each gateway to serve HTTPS.

| Gateway | HTTPS works | Cert used | HTTP to HTTPS redirect |
|---------|------------|-----------|------------------------|
| NGINX | Yes — HTTP/2 200 | Own self-signed cert (ignores mkcert) | Yes — 308 Redirect |
| Traefik | Yes — HTTP/2 200 | mkcert cert (locally trusted) | Yes — auto redirect |
| HAProxy | not tested | not tested | not tested |
| Kong | not tested | not tested | not tested |
| Envoy | not tested | not tested | not tested |

Key findings:
- Traefik automatically picked up the mkcert TLS secret — no extra config needed
- NGINX defaulted to its own Fake Certificate even with the secret present
- Both gateways returned 308 Permanent Redirect when client hit HTTP :8080
- Backend pod only ever sees plain HTTP — TLS is fully terminated at the gateway
- X-Forwarded-Proto: https tells the backend the original request was secure

---

## 4. What Each X-Forwarded Header Does

| Header | What it tells the backend | Real use case |
|--------|--------------------------|---------------|
| X-Forwarded-For | Client real IP address | Rate limiting, geo-blocking, security logs |
| X-Forwarded-Proto | http or https | Only allow secure actions over HTTPS |
| X-Forwarded-Host | Original domain the client hit | Multi-tenant apps |
| X-Forwarded-Port | Port the client connected to | Building correct redirect URLs |

Without these headers the backend only sees the internal cluster IP
and has no idea who the real client is or how they connected.

---

## 5. NGINX vs Traefik — Head to Head

| | NGINX | Traefik |
|---|---|---|
| Setup complexity | Medium — needs extra flags | Low — plug and play |
| X-Forwarded headers | Works with config | Works out of the box |
| TLS cert handling | Uses own cert by default | Picks up mkcert cert correctly |
| HTTP to HTTPS redirect | 308 redirect | Auto redirect |
| Performance | 5,326 req/s | 5,923 req/s |
| Best for | Production, WAF, fine control | Simple setup, dev environments |

---

## 6. Pending (Docker crashed during testing)

- HAProxy — X-Forwarded headers and TLS not tested
- Kong — X-Forwarded headers and TLS not tested
- Envoy — X-Forwarded headers and TLS not tested
- X-Forwarded-Port — not added yet, planned next
- IP whitelisting/blacklisting — not implemented yet
