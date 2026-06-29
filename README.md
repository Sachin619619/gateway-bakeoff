# Gateway Bake-off (Local)

Compare ingress/gateway options **locally** by putting the same sample app
(`httpbin`) behind each one, load-testing them, and scoring the results.

**Everything runs only on your machine** — a local Kubernetes cluster (kind).
Nothing is exposed to the internet. You reach each gateway via `kubectl
port-forward` to `localhost` by default. Optional LoadBalancer mode is also
available with MetalLB for testing a more realistic service exposure path.

Dedicated LoadBalancer results are in
[`docs/LOAD_BALANCER_RESULTS.md`](docs/LOAD_BALANCER_RESULTS.md).

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

Install all required tools (macOS):

```bash
# kind    — creates a local Kubernetes cluster inside Docker
# kubectl — CLI to talk to the Kubernetes cluster
# helm    — package manager to install gateways (NGINX, Traefik, etc.)
# k6      — load testing tool
# mkcert  — generates locally-trusted TLS certificates (no browser warning)
# nss     — required by mkcert to trust certs in Firefox
brew install kind kubectl helm k6 mkcert nss

# Installs mkcert's local CA into your system trust store
# so curl/browser trusts the generated certs without the -k flag
# Note: this requires your laptop password (sudo) once
mkcert -install

# Make sure Docker Desktop is running before proceeding
# kind needs Docker to create the cluster nodes as containers
```

> **On Ubuntu/Linux?** See **[RUN_UBUNTU.md](RUN_UBUNTU.md)** for the full
> copy-paste guide (tool installs + every command, Linux-flavored).

---

## 1. Create the local cluster + deploy the sample app (once)

```bash
# Clone the repo first (on a new laptop)
git clone https://github.com/Sachin619619/gateway-bakeoff.git  # replace with your fork URL if needed
cd gateway-bakeoff

# Creates a single-node Kubernetes cluster named "bakeoff" inside Docker
# Also sets kubectl context to "kind-bakeoff" automatically
kind create cluster --name bakeoff --wait 120s

# Deploys httpbin — the shared backend app all gateways will proxy to
# httpbin echoes back request headers, which lets us verify X-Forwarded headers
kubectl apply -f manifests/httpbin.yaml

# Waits until both httpbin pods are up and ready before proceeding
kubectl rollout status deploy/httpbin
```

### 1a. Generate TLS certificate (for HTTPS tests)

```bash
# Creates the certs/ folder to store the certificate files
mkdir -p certs

# Generates a TLS certificate valid for localhost and 127.0.0.1
# tls.crt = the public certificate, tls.key = the private key
mkcert -cert-file certs/tls.crt -key-file certs/tls.key localhost 127.0.0.1

# Creates a Kubernetes secret from the cert files
# The gateways will read this secret to serve HTTPS
kubectl create secret tls httpbin-tls --cert=certs/tls.crt --key=certs/tls.key
```

> The `certs/` folder is gitignored — you must run the above on each new laptop.
> Run `mkcert -install` first so curl trusts the cert without the `-k` flag.

---

## 2. Test each gateway (one at a time)

**Rule:** install one gateway → apply route → port-forward → verify headers → load test → uninstall.
One at a time avoids port conflicts and keeps measurements fair.

> **macOS note:** `sed -i ''` is macOS syntax. On Linux use `sed -i` (no quotes).
> If a port-forward target is not found, run `kubectl get svc -A` to check service names.

---

### Optional: local LoadBalancer mode

The default bake-off uses `kubectl port-forward` because it is simple and works
on every local machine. If you also want to test `service.type=LoadBalancer`,
install MetalLB once:

```bash
bash scripts/install-metallb.sh
```

Then install the gateway with a LoadBalancer service instead of `ClusterIP`.
Example for NGINX:

```bash
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true"
```

Verify the assigned IP and run the same load test against it:

```bash
bash scripts/verify-loadbalancer.sh ingress-nginx nginx-ingress-nginx-controller

# Use the IP printed by the verification script:
LB_IP="172.18.0.200" # replace with the IP printed by the script
BASE="http://${LB_IP}:80" k6 run k6-test.js
```

Full steps are in **[docs/LOAD_BALANCER.md](docs/LOAD_BALANCER.md)**.

---

### 2a. NGINX Ingress

```bash
# Add the NGINX Ingress Helm chart repository and refresh the local cache
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update

# Install NGINX Ingress controller in its own namespace
# --set controller.service.type=ClusterIP         → no external LoadBalancer needed (we use port-forward)
# --set controller.admissionWebhooks.enabled=false → skips webhook setup (not needed for local testing)
# --set controller.config.use-forwarded-headers    → tells NGINX to trust and pass X-Forwarded-For from clients
# --set controller.config.compute-full-forwarded-for → appends each hop's IP to X-Forwarded-For chain
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=ClusterIP \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.config.use-forwarded-headers="true" \
  --set controller.config.compute-full-forwarded-for="true"

# Waits until the NGINX controller pod is fully running before we route traffic
kubectl -n ingress-nginx rollout status deploy/nginx-ingress-nginx-controller --timeout=150s

# Updates the ingress manifest to use NGINX as the ingress class
sed -i '' 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress-tls.yaml

# Applies the HTTP ingress route — tells NGINX to forward / → httpbin service
kubectl apply -f manifests/ingress.yaml

# Applies the HTTPS ingress route — tells NGINX to terminate TLS using the httpbin-tls secret
kubectl apply -f manifests/ingress-tls.yaml

# Forwards localhost:8080 → NGINX HTTP port (80) and localhost:8443 → NGINX HTTPS port (443)
# Run this in a terminal and keep it running while you test
kubectl -n ingress-nginx port-forward svc/nginx-ingress-nginx-controller 8080:80 8443:443 &

# Sanity check — should return JSON with request details from httpbin
curl -s http://localhost:8080/get | head

# Verify X-Forwarded headers and TLS (see Step 3 below)
bash scripts/verify-headers.sh https 8443

# Run the load test (see Step 4 below)
k6 run k6-test.js

# --- Cleanup: stop port-forward, remove routes, uninstall NGINX ---
# Press Ctrl+C in the port-forward terminal, then:
kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall nginx -n ingress-nginx
```

---

### 2b. Traefik

```bash
# Add the Traefik Helm chart repository and refresh the local cache
helm repo add traefik https://traefik.github.io/charts && helm repo update

# Install Traefik in its own namespace
# --set service.type=ClusterIP → no external LoadBalancer, we use port-forward
helm install traefik traefik/traefik -n traefik --create-namespace --set service.type=ClusterIP

# Waits until Traefik pod is fully running
kubectl -n traefik rollout status deploy/traefik --timeout=150s

# Updates ingress manifests to use Traefik as the ingress class
sed -i '' 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress-tls.yaml

kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

# Forwards localhost:8080 → Traefik HTTP and localhost:8443 → Traefik HTTPS
kubectl -n traefik port-forward svc/traefik 8080:80 8443:443 &

bash scripts/verify-headers.sh https 8443
k6 run k6-test.js

kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall traefik -n traefik
```

---

### 2c. HAProxy

```bash
# Add the HAProxy Tech Helm chart repository
helm repo add haproxytech https://haproxytech.github.io/helm-charts && helm repo update

helm install haproxy haproxytech/kubernetes-ingress -n haproxy --create-namespace \
  --set controller.service.type=ClusterIP

kubectl -n haproxy rollout status deploy/haproxy-kubernetes-ingress --timeout=150s

sed -i '' 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress-tls.yaml

kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

kubectl -n haproxy port-forward svc/haproxy-kubernetes-ingress 8080:80 8443:443 &

bash scripts/verify-headers.sh https 8443
k6 run k6-test.js

kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall haproxy -n haproxy
```

---

### 2d. Kong

```bash
# Add the Kong Helm chart repository
helm repo add kong https://charts.konghq.com && helm repo update

helm install kong kong/kong -n kong --create-namespace --set proxy.type=ClusterIP

# Kong takes a bit longer to start — 180s timeout
kubectl -n kong rollout status deploy/kong-kong --timeout=180s

sed -i '' 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress.yaml
sed -i '' 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress-tls.yaml

kubectl apply -f manifests/ingress.yaml
kubectl apply -f manifests/ingress-tls.yaml

# Kong proxy service name is kong-kong-proxy
kubectl -n kong port-forward svc/kong-kong-proxy 8080:80 8443:443 &

bash scripts/verify-headers.sh https 8443
k6 run k6-test.js

kubectl delete -f manifests/ingress.yaml
kubectl delete -f manifests/ingress-tls.yaml
helm uninstall kong -n kong
```

---

### 2e. Envoy Gateway

```bash
# Envoy uses the newer Gateway API (not the classic Ingress API)
# so it uses envoy-gateway.yaml instead of ingress.yaml
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  -n envoy-gateway-system --create-namespace

kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s

# Apply Envoy-specific Gateway API route (GatewayClass + Gateway + HTTPRoute)
kubectl apply -f manifests/envoy-gateway.yaml

# Envoy creates a dynamically named proxy service — find its exact name first
SVC=$(kubectl -n envoy-gateway-system get svc -o name | grep envoy-default-eg)

# Forward that service to localhost:8080
kubectl -n envoy-gateway-system port-forward "$SVC" 8080:80 &

bash scripts/verify-headers.sh http 8080
k6 run k6-test.js

kubectl delete -f manifests/envoy-gateway.yaml
helm uninstall eg -n envoy-gateway-system
```

---

## 3. Verify X-Forwarded headers + HTTPS

With a gateway port-forwarded (HTTP on 8080, HTTPS on 8443), run:

```bash
# Runs 4 checks in one shot:
# 1. Sends X-Forwarded-For: 203.0.113.99 and checks if backend received it
# 2. Checks if backend received X-Forwarded-Proto: https (set by gateway on TLS termination)
# 3. Checks if backend received X-Forwarded-Host (original Host header preserved)
# 4. Checks TLS — connects on 8443 and shows which cert the gateway is serving
bash scripts/verify-headers.sh https 8443

# For HTTP-only gateways (e.g. Envoy in this setup):
bash scripts/verify-headers.sh http 8080
```

See **[OBSERVATIONS.md](OBSERVATIONS.md)** for the actual measured results per gateway.

---

## 4. Load test

```bash
# Quick sanity check first — should return JSON from httpbin
curl -s localhost:8080/get | head

# Runs the k6 load test: ramps to 50 concurrent users over 20s,
# holds for 1 minute, then ramps down. Total ~90s.
# Thresholds: p95 latency < 500ms, error rate < 1%
k6 run k6-test.js

# If testing LoadBalancer mode, override the target:
LB_IP="172.18.0.200" # replace with the IP printed by the script
BASE="http://${LB_IP}:80" k6 run k6-test.js
```

From the k6 summary, record into `scorecard.md`:
- `http_reqs` rate → **Req/s**
- `http_req_duration` p(95) and median → **p95 / p50 latency**
- `http_req_failed` rate → **Error rate**

---

## 5. Optional feature checks

```bash
# Rate limiting — send 50 requests rapidly, watch for 429 Too Many Requests
for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" localhost:8080/get; done

# WAF check (NGINX + ModSecurity) — send a XSS attack string, expect 403 blocked
curl -s -o /dev/null -w "%{http_code}\n" "localhost:8080/get?x=<script>alert(1)</script>"
```

---

## 6. Score & decide

Fill in `scorecard.md`. Weight **operational fit** (your team's skills, how it
will actually be run) alongside the raw numbers — the fastest gateway isn't
automatically the right one. See the Results & Recommendation at the top.

---

## 7. Tear it all down

```bash
# Deletes the entire kind cluster and all resources inside it
# This removes everything — no leftover containers or namespaces
kind delete cluster --name bakeoff
```

---

## License

Released under the [MIT License](LICENSE).
