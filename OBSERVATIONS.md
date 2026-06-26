# Gateway Bake-off — Observations

Tests run on: local kind cluster (single-node), macOS Apple Silicon  
Gateways: NGINX Ingress, Traefik, HAProxy, Kong, Envoy  
Backend: httpbin (2 replicas)  
Test tool: `scripts/verify-headers.sh`

---

## 1. X-Forwarded Headers

### What we tested
Sent a request with `X-Forwarded-For: 203.0.113.99` and checked if the backend received:
- `X-Forwarded-For` — client IP
- `X-Forwarded-Proto` — HTTP or HTTPS
- `X-Forwarded-Host` — original host header

### Results

| Gateway | X-Forwarded-For | X-Forwarded-Proto | X-Forwarded-Host | Notes |
|---------|----------------|-------------------|------------------|-------|
| NGINX | ✅ `203.0.113.99, 127.0.0.1` | ✅ `https` | ✅ `localhost` | Appends its own IP to the chain |
| Traefik | ✅ `127.0.0.1` | ✅ `https` | ✅ `localhost` | Passes proto and host correctly |
| HAProxy | — | — | — | Pending test |
| Kong | — | — | — | Pending test |
| Envoy | — | — | — | Pending test |

### Key Observations
- **NGINX** appends its own IP to `X-Forwarded-For` (chain: `client → gateway`). Configured via `use-forwarded-headers=true` and `compute-full-forwarded-for=true`.
- **Traefik** passes `X-Forwarded-Proto` as `https` automatically when TLS is terminated — no extra config needed.
- Both gateways correctly set `X-Forwarded-Host` from the original `Host` header.

---

## 2. HTTP → HTTPS (TLS Termination)

### What we tested
Generated a local certificate using `mkcert` for `localhost` and `127.0.0.1`, created a Kubernetes TLS secret (`httpbin-tls`), and configured each gateway to terminate TLS.

### How to generate the cert
```bash
mkcert -cert-file certs/tls.crt -key-file certs/tls.key localhost 127.0.0.1
kubectl create secret tls httpbin-tls --cert=certs/tls.crt --key=certs/tls.key
```

### Results

| Gateway | HTTPS Working | Cert Used | HTTP → HTTPS Redirect | Notes |
|---------|--------------|-----------|----------------------|-------|
| NGINX | ✅ HTTP/2 200 | ❌ Default self-signed (Fake Certificate) | ✅ 308 Redirect | NGINX uses its own cert by default; mkcert cert needs explicit TLS secret ref in ingress |
| Traefik | ✅ HTTP/2 200 | ✅ mkcert cert (`/O=mkcert development certificate`) | ✅ Auto | Traefik picked up the TLS secret correctly from the ingress spec |
| HAProxy | — | — | — | Pending test |
| Kong | — | — | — | Pending test |
| Envoy | — | — | — | Pending test |

### Key Observations
- **Traefik** automatically used our `mkcert` cert from the TLS secret — cleanest experience.
- **NGINX** defaulted to its own self-signed "Fake Certificate" despite the TLS secret being present — requires explicit `secretName` to be picked up correctly in production setups.
- HTTP → HTTPS redirect worked on both: NGINX returned `308 Permanent Redirect`, Traefik redirected automatically.
- `mkcert -install` requires sudo to trust the CA system-wide; without it, curl needs `-sk` flag (skip cert verify). On another laptop, run `mkcert -install` first.

---

## 3. Summary Table (completed gateways)

| Feature | NGINX | Traefik | HAProxy | Kong | Envoy |
|---------|-------|---------|---------|------|-------|
| X-Forwarded-For passthrough | ✅ | ✅ | — | — | — |
| X-Forwarded-Proto | ✅ | ✅ | — | — | — |
| X-Forwarded-Host | ✅ | ✅ | — | — | — |
| TLS termination | ✅ | ✅ | — | — | — |
| mkcert cert used | ❌ (own cert) | ✅ | — | — | — |
| HTTP → HTTPS redirect | ✅ | ✅ | — | — | — |
