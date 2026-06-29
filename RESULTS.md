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
| HAProxy | 10.244.0.1 | https | not emitted | No extra config in this test |
| Kong | 10.244.0.1 | https | localhost | No extra config in this test |
| Envoy | 10.244.0.35 | https | not emitted | Gateway API HTTPS listener added |

Key findings:
- NGINX needs use-forwarded-headers=true and compute-full-forwarded-for=true flags at install
- NGINX appends its own gateway IP to X-Forwarded-For (full hop chain)
- Traefik injects all 3 headers automatically with zero config
- All five correctly passed X-Forwarded-Proto as https after TLS termination
- Kong passed X-Forwarded-Host; HAProxy and Envoy did not emit it by default in
  this local LoadBalancer verification

---

## 3. TLS Termination (HTTPS)

What we tested: generated a local cert with mkcert, stored it as a
Kubernetes TLS secret, and configured each gateway to serve HTTPS.

| Gateway | HTTPS works | Cert used | HTTP to HTTPS redirect |
|---------|------------|-----------|------------------------|
| NGINX | Yes — HTTP/2 200 | Own self-signed cert (ignores mkcert) | Yes — 308 Redirect |
| Traefik | Yes — HTTP/2 200 | mkcert cert (locally trusted) | Yes — auto redirect |
| HAProxy | Yes | Kubernetes TLS secret | Redirect not measured in this retest |
| Kong | Yes | Kubernetes TLS secret | Redirect not measured in this retest |
| Envoy | Yes | Kubernetes TLS secret | Gateway API listener, redirect not configured |

Key findings:
- Traefik automatically picked up the mkcert TLS secret — no extra config needed
- NGINX defaulted to its own Fake Certificate even with the secret present
- NGINX and Traefik returned 308 Permanent Redirect when client hit HTTP :8080
- HAProxy, Kong, and Envoy Gateway were verified for HTTPS termination through
  the LoadBalancer IP
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

## 6. Earlier Pending Items

- Docker was recovered and the LoadBalancer benchmark was completed for all
  five gateways.
- HAProxy, Kong, and Envoy Gateway were retested through the MetalLB
  LoadBalancer path.
- IP whitelisting/blacklisting is still not implemented.

---

## 7. LoadBalancer Mode

Tested on: 2026-06-29, local kind cluster, MetalLB `172.19.0.200-172.19.0.250` pool
Backend: httpbin (2 replicas)
Load test: k6, 50 virtual users, ~90 seconds

Important local note: on Docker Desktop for macOS, the MetalLB Docker-network IP
was reachable from inside the kind/Docker network, but not directly from the
macOS host. For that reason, the LoadBalancer benchmark was run as a k6 pod in
the cluster against the MetalLB IP.

| Gateway | LB IP | HTTP via LB IP | HTTPS via LB IP | Req/s | p50 | p95 | Errors |
|---------|-------|----------------|-----------------|-------|-----|-----|--------|
| NGINX | 172.19.0.200 | Yes | Yes | 24,093 | 1.18 ms | 4.69 ms | 0% |
| Traefik | 172.19.0.200 | Yes | Yes | 24,069 | 1.26 ms | 4.44 ms | 0% |
| HAProxy | 172.19.0.200 | Yes | Yes | 24,375 | 1.02 ms | 5.06 ms | 0% |
| Kong | 172.19.0.200 | Yes | Yes | 21,709 | 1.38 ms | 4.86 ms | 0% |
| Envoy Gateway | 172.19.0.200 | Yes | Yes | 18,708 | 1.50 ms | 5.99 ms | 0% |

Verification details:
- MetalLB assigned `172.19.0.200`
- NGINX, Traefik, HAProxy, Kong, and Envoy Gateway served HTTP through the
  LoadBalancer IP
- NGINX, Traefik, HAProxy, Kong, and Envoy Gateway served HTTPS through the
  LoadBalancer IP
- NGINX, Traefik, and Kong forwarded `X-Forwarded-For`,
  `X-Forwarded-Host`, `X-Forwarded-Port`, and `X-Forwarded-Proto`
- HAProxy forwarded `X-Forwarded-For` and `X-Forwarded-Proto`
- Envoy Gateway forwarded `X-Forwarded-For` and `X-Forwarded-Proto`
- k6 thresholds passed for all five gateways

Result: all five gateways work correctly in local LoadBalancer mode for HTTP
traffic and terminate TLS correctly.
Throughput is much higher than the earlier host `port-forward` results because
this test runs from inside the cluster network and avoids the local
`kubectl port-forward` bottleneck. Treat these as LoadBalancer-mode local
measurements, not direct apples-to-apples replacements for the earlier
port-forward table.

Note: Envoy Gateway uses Gateway API instead of classic Kubernetes Ingress.
Its HTTPS test requires TLS SNI to match the listener hostname, so the
verification used `curl --resolve localhost:443:172.19.0.200`.
