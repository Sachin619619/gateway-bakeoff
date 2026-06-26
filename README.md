# Gateway Bake-off (Local)

Compare ingress/gateway options **locally** by putting the same sample app
(`httpbin`) behind each one, load-testing them, and scoring the results.

**Everything runs only on your machine** — a local Kubernetes cluster (kind).
Nothing is exposed to the internet. You reach each gateway via `kubectl
port-forward` to `localhost`.

## Gateways covered
NGINX Ingress · Traefik · HAProxy · Kong · Envoy Gateway

> **Azure Application Gateway is excluded** — it is a cloud-only managed service
> and cannot run locally.

---

## Results & Recommendation (measured 2026-06-23, local kind cluster)

Load test: k6, 50 virtual users, ~90s, against `httpbin` via each gateway.
All gateways returned **0% errors** — every one is stable.

| Rank | Gateway        | Req/s | p50    | p95     | Errors |
|------|----------------|-------|--------|---------|--------|
| 1    | HAProxy        | 6,665 | 5.5 ms | 12.2 ms | 0%     |
| 2    | Traefik        | 5,923 | 6.3 ms | 13.4 ms | 0%     |
| 3    | NGINX Ingress  | 5,326 | 6.7 ms | 15.9 ms | 0%     |
| 4    | Kong           | 5,123 | 7.0 ms | 17.1 ms | 0%     |
| 5    | Envoy Gateway  | 4,789 | 7.2 ms | 18.4 ms | 0%     |

**Recommendation: NGINX Ingress (+ ModSecurity WAF).** The performance spread is
small and all options are fast and stable, so maturity, ecosystem, and a
built-in WAF path win — NGINX is the lowest-risk, K8s-native default.

- Pick **HAProxy** instead if raw throughput is the #1 priority (clearly fastest).
- Pick **Kong** if you need API-gateway features (auth, API keys, plugins, portal).

> Caveats: single-node kind cluster on a laptop, accessed via `port-forward`
> (a throughput bottleneck), testing raw `GET` proxying only. Treat numbers as
> **relative**, not production capacity — the ranking matches each tool's profile.

---

## 0. Prerequisites

```bash
brew install kind kubectl helm k6 mkcert nss
mkcert -install   # installs local CA into system trust store (requires sudo/password once)
# Docker Desktop (or Colima) must be running — kind needs a container runtime.
```

> **On Ubuntu/Linux?** See **[RUN_UBUNTU.md](RUN_UBUNTU.md)** for the full
> copy-paste guide (tool installs + every command, Linux-flavored).

---

## 1. Create the local cluster + deploy the sample app (once)

A single-node cluster is plenty for this and is the most reliable:

```bash
cd gateway-bakeoff
kind create cluster --name bakeoff --wait 120s   # kind sets kubectl context "kind-bakeoff"
kubectl apply -f manifests/httpbin.yaml
kubectl rollout status deploy/httpbin
```

`httpbin` is the shared backend for every gateway, so comparisons are fair.
(`kind-config.yaml` is included if you ever want a multi-node cluster — pass
`--config kind-config.yaml` — but single-node is recommended here.)

### 1a. Generate TLS certificate (for HTTPS tests)

```bash
mkdir -p certs
mkcert -cert-file certs/tls.crt -key-file certs/tls.key localhost 127.0.0.1
kubectl create secret tls httpbin-tls --cert=certs/tls.crt --key=certs/tls.key
```

> The `certs/` folder is gitignored. You must regenerate the cert on each new laptop.
> Run `mkcert -install` first so your browser/curl trusts the cert without `-k`.

---

## 2. Test each gateway (one at a time)

For each gateway: **install → route → port-forward → load test → record → uninstall.**
Doing one at a time avoids port clashes and keeps measurements clean. Commands
below are the exact ones verified working on macOS + kind.

> The `sed -i ''` line is macOS syntax (Linux: use `sed -i`). It just sets the
> `ingressClassName` in `manifests/ingress.yaml` for the gateway under test.
> Tip: if a port-forward target isn't found, run `kubectl get svc -A`.

### 2a. NGINX Ingress
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=ClusterIP \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true"
kubectl -n ingress-nginx rollout status deploy/nginx-ingress-nginx-controller --timeout=150s

sed -i '' 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress-tls.yaml
kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

# HTTP + HTTPS port-forward
kubectl -n ingress-nginx port-forward svc/nginx-ingress-nginx-controller 8080:80 8443:443 &
# Verify headers:       bash scripts/verify-headers.sh https 8443
# Load test (HTTP):     k6 run k6-test.js
# record results, Ctrl-C the port-forward, then clean up:
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall nginx -n ingress-nginx
```

### 2b. Traefik
```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace --set service.type=ClusterIP
kubectl -n traefik rollout status deploy/traefik --timeout=150s

sed -i '' 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress-tls.yaml
kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

# HTTP + HTTPS port-forward (Traefik web=8000, websecure=8443)
kubectl -n traefik port-forward svc/traefik 8080:80 8443:443 &
# Verify headers:       bash scripts/verify-headers.sh https 8443
# Load test (HTTP):     k6 run k6-test.js
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall traefik -n traefik
```

### 2c. HAProxy
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts && helm repo update
helm install haproxy haproxytech/kubernetes-ingress -n haproxy --create-namespace \
  --set controller.service.type=ClusterIP
kubectl -n haproxy rollout status deploy/haproxy-kubernetes-ingress --timeout=150s

sed -i '' 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress-tls.yaml
kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

kubectl -n haproxy port-forward svc/haproxy-kubernetes-ingress 8080:80 8443:443 &
# Verify headers:       bash scripts/verify-headers.sh https 8443
# Load test (HTTP):     k6 run k6-test.js
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall haproxy -n haproxy
```

### 2d. Kong
```bash
helm repo add kong https://charts.konghq.com && helm repo update
helm install kong kong/kong -n kong --create-namespace --set proxy.type=ClusterIP
kubectl -n kong rollout status deploy/kong-kong --timeout=180s

sed -i '' 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress-tls.yaml
kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

kubectl -n kong port-forward svc/kong-kong-proxy 8080:80 8443:443 &
# Verify headers:       bash scripts/verify-headers.sh https 8443
# Load test (HTTP):     k6 run k6-test.js
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall kong -n kong
```

### 2e. Envoy Gateway (uses Gateway API, not Ingress)
```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  -n envoy-gateway-system --create-namespace
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s

kubectl apply -f manifests/envoy-gateway.yaml
# Envoy creates a proxy service named envoy-default-eg-<hash>; grab its real name:
SVC=$(kubectl -n envoy-gateway-system get svc -o name | grep envoy-default-eg)
kubectl -n envoy-gateway-system port-forward "$SVC" 8080:80
# new terminal:  curl -s localhost:8080/get ;  k6 run k6-test.js
kubectl delete -f manifests/envoy-gateway.yaml ; helm uninstall eg -n envoy-gateway-system
```

---

## 3. Verify X-Forwarded headers + HTTPS

With a gateway port-forwarded to `localhost:8080` (HTTP) and `localhost:8443` (HTTPS):

```bash
# Test X-Forwarded headers + TLS in one shot
bash scripts/verify-headers.sh https 8443
```

This checks:
- `X-Forwarded-For` — client IP reaches the backend (with gateway IP appended)
- `X-Forwarded-Proto` — backend sees `https` when TLS is terminated at gateway
- `X-Forwarded-Host` — original `Host` header is preserved
- TLS cert info — which cert the gateway is serving

See **[OBSERVATIONS.md](OBSERVATIONS.md)** for measured results per gateway.

---

## 4. Load test

With a gateway port-forwarded to `localhost:8080`:

```bash
curl -s localhost:8080/get | head   # sanity check the route first
k6 run k6-test.js
```

From the k6 summary, copy into `scorecard.md`:
- **http_reqs** rate → Req/s
- **http_req_duration** `p(95)` (and `med` for p50)
- **http_req_failed** rate → Error rate

---

## 4. Optional feature checks (quick, manual)

Exercise the rows beyond raw routing:

- **Rate limiting** — enable it, then
  `for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/get; done`
  and watch for `429`s.
- **WAF** (NGINX + ModSecurity) — send an obvious attack, expect a block:
  `curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/get?x=<script>alert(1)</script>"`
- **TLS termination** — add a self-signed cert (`mkcert`) and hit `https://`.
- **Auth** — turn on basic/key auth, confirm `401` without credentials.

> Auto-SSL via Let's Encrypt won't work locally (needs a public domain). Use
> `mkcert`/self-signed for local HTTPS — that table row is moot here.

---

## 5. Score & decide

Fill in `scorecard.md`. Weight **operational fit** (your team's skills, how it
will actually be run) alongside the raw numbers — the fastest gateway isn't
automatically the right one. See the Results & Recommendation at the top.

---

## 6. Tear it all down

```bash
kind delete cluster --name bakeoff
```

Everything was local and disposable — this removes it completely.

---

### Want to add Istio Gateway too?
Istio is also Envoy-based. Install Istio (`istioctl install`) and use its
`Gateway` + `VirtualService` against the same `httpbin`. Ask and I'll add a
`2f` section + manifests.

---

## License

Released under the [MIT License](LICENSE).
