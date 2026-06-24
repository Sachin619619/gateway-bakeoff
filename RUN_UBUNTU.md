# Running the Bake-off on Ubuntu — Every Command (Explained)

Step-by-step, copy-paste guide to run the full gateway bake-off on Ubuntu.
**Every command has a `#` comment explaining what it does.** Everything runs
locally; nothing is exposed to the internet.

> Need ~15 GB free disk — the cluster + 5 gateway images need room.

**The big picture:** you create one local Kubernetes cluster, deploy a tiny test
app (`httpbin`) once, then put each gateway in front of it one at a time and
hammer it with a load test (`k6`). Same backend every time = a fair comparison.

---

## 0. Install everything (one-time)

### Docker — the container engine that runs the whole cluster
```bash
sudo apt-get update                              # refresh the package list
sudo apt-get install -y docker.io curl           # install Docker + curl
sudo systemctl enable --now docker               # start Docker now + on every boot
sudo usermod -aG docker $USER                    # let your user run docker without sudo
newgrp docker                                    # apply that group change in this shell
docker info >/dev/null && echo "Docker OK"       # confirm Docker is reachable
```

### kind — runs a Kubernetes cluster *inside* Docker containers
```bash
# look up the latest kind version from GitHub:
KIND_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep tag_name | cut -d '"' -f4)
# download that version's Linux binary:
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-amd64"
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind   # make it executable + put it on PATH
```

### kubectl — the command-line tool to talk to the cluster
```bash
# download the latest stable kubectl for Linux:
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/      # make executable + put on PATH
```

### helm — the package manager used to install each gateway
```bash
# official helm install script (fetches + installs the latest helm):
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### k6 — the load-testing tool that measures each gateway
Install from k6's official **GitHub release binary**. This is the most reliable
method — no apt repo and no GPG signing key — so it works in containers,
Codespaces, and locked-down/corporate networks where the apt-key method fails
with `NO_PUBKEY` / "repository is not signed" errors.
```bash
sudo apt-get install -y curl tar                              # tools to fetch + extract
# find the latest k6 version tag from GitHub:
K6_VER=$(curl -fsSL https://api.github.com/repos/grafana/k6/releases/latest | grep -oP '"tag_name": "\K[^"]+')
# download + extract the prebuilt binary, then put it on your PATH:
curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VER}/k6-${K6_VER}-linux-amd64.tar.gz" -o /tmp/k6.tar.gz
tar -xzf /tmp/k6.tar.gz -C /tmp
sudo mv /tmp/k6-*/k6 /usr/local/bin/k6
k6 version                                                    # confirm it installed
```

> **Alternatives (only if the binary method above doesn't suit you):**
> - **Snap** (needs snapd): `sudo snap install k6`
> - **apt repo** (standard desktops): fetch k6's key over HTTPS, then add the repo —
>   `curl -fsSL https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg`
>   then `echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list && sudo apt-get update && sudo apt-get install -y k6`.
>   **Avoid** the old `gpg --recv-keys <fingerprint>` keyserver method — it needs
>   `dirmngr` and hard-codes a key that goes stale, causing `NO_PUBKEY` errors.
> - **If a previous apt attempt left a broken k6 repo** (apt update keeps erroring):
>   `sudo rm -f /etc/apt/sources.list.d/k6.list && sudo apt-get update`

### Verify everything installed
```bash
docker --version && kind version && kubectl version --client && helm version && k6 version
```

---

## 1. Create the cluster + deploy the sample app (once)

```bash
cd gateway-bakeoff
kind create cluster --name bakeoff --wait 120s   # build a local K8s cluster, wait until it's ready
kubectl apply -f manifests/httpbin.yaml          # deploy httpbin (the shared test backend)
kubectl rollout status deploy/httpbin            # wait until httpbin pods are running
```

`httpbin` stays up the whole time — every gateway routes to this same app.

---

## 2. Test each gateway (run one block, record results, move to next)

> Each block follows the same pattern, explained inline:
> **install the gateway → point a route at httpbin → open a local tunnel to it
> → load test → tear it down before the next one.**
> On Ubuntu `sed -i` needs **no** `''` (that's a macOS quirk).

### 2a. NGINX Ingress
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update   # add NGINX's helm chart repo
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=ClusterIP \          # keep it internal (we reach it via port-forward)
  --set controller.admissionWebhooks.enabled=false   # skip the webhook (not needed locally, avoids delays)
kubectl -n ingress-nginx rollout status deploy/nginx-ingress-nginx-controller --timeout=150s   # wait until ready

sed -i 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress.yaml   # tell the route to use NGINX
kubectl apply -f manifests/ingress.yaml             # create the route (httpbin -> NGINX)

kubectl -n ingress-nginx port-forward svc/nginx-ingress-nginx-controller 8080:80 >/tmp/pf.log 2>&1 &   # tunnel localhost:8080 -> gateway
PF=$!; sleep 3                                       # save the tunnel's process id, give it a moment
curl -s localhost:8080/get | head -3                # sanity check: does the route work?
k6 run k6-test.js                                   # LOAD TEST -> record req/s, p95, error rate
kill $PF                                             # close the tunnel

kubectl delete -f manifests/ingress.yaml ; helm uninstall nginx -n ingress-nginx   # clean up before the next gateway
```

### 2b. Traefik
```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update          # add Traefik's chart repo
helm install traefik traefik/traefik -n traefik --create-namespace --set service.type=ClusterIP   # install (internal service)
kubectl -n traefik rollout status deploy/traefik --timeout=150s                     # wait until ready

sed -i 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress.yaml   # route via Traefik
kubectl apply -f manifests/ingress.yaml                                             # create the route

kubectl -n traefik port-forward svc/traefik 8080:80 >/tmp/pf.log 2>&1 &             # tunnel to the gateway
PF=$!; sleep 3
curl -s localhost:8080/get | head -3                                                # sanity check
k6 run k6-test.js                                                                   # load test -> record
kill $PF                                                                            # close tunnel

kubectl delete -f manifests/ingress.yaml ; helm uninstall traefik -n traefik        # clean up
```

### 2c. HAProxy
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts && helm repo update   # add HAProxy's chart repo
helm install haproxy haproxytech/kubernetes-ingress -n haproxy --create-namespace \
  --set controller.service.type=ClusterIP                                           # install (internal service)
kubectl -n haproxy rollout status deploy/haproxy-kubernetes-ingress --timeout=150s   # wait until ready

sed -i 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress.yaml    # route via HAProxy
kubectl apply -f manifests/ingress.yaml                                              # create the route

kubectl -n haproxy port-forward svc/haproxy-kubernetes-ingress 8080:80 >/tmp/pf.log 2>&1 &   # tunnel to the gateway
PF=$!; sleep 3
curl -s localhost:8080/get | head -3                                                 # sanity check
k6 run k6-test.js                                                                    # load test -> record
kill $PF                                                                             # close tunnel

kubectl delete -f manifests/ingress.yaml ; helm uninstall haproxy -n haproxy         # clean up
```

### 2d. Kong
```bash
helm repo add kong https://charts.konghq.com && helm repo update                     # add Kong's chart repo
helm install kong kong/kong -n kong --create-namespace --set proxy.type=ClusterIP    # install (internal proxy service)
kubectl -n kong rollout status deploy/kong-kong --timeout=180s                       # wait until ready

sed -i 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress.yaml        # route via Kong
kubectl apply -f manifests/ingress.yaml                                              # create the route

kubectl -n kong port-forward svc/kong-kong-proxy 8080:80 >/tmp/pf.log 2>&1 &          # tunnel to the gateway
PF=$!; sleep 3
curl -s localhost:8080/get | head -3                                                 # sanity check
k6 run k6-test.js                                                                    # load test -> record
kill $PF                                                                             # close tunnel

kubectl delete -f manifests/ingress.yaml ; helm uninstall kong -n kong               # clean up
```

### 2e. Envoy Gateway (uses the Gateway API, not Ingress)
```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm -n envoy-gateway-system --create-namespace   # install Envoy Gateway
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s   # wait until its control plane is ready

kubectl apply -f manifests/envoy-gateway.yaml        # create GatewayClass + Gateway + HTTPRoute (the Gateway-API way)
sleep 10                                             # give Envoy a moment to spin up the proxy
SVC=$(kubectl -n envoy-gateway-system get svc -o name | grep envoy-default-eg)   # find the auto-named proxy service
kubectl -n envoy-gateway-system port-forward "$SVC" 8080:80 >/tmp/pf.log 2>&1 &   # tunnel to that proxy
PF=$!; sleep 3
curl -s localhost:8080/get | head -3                 # sanity check
k6 run k6-test.js                                    # load test -> record
kill $PF                                             # close tunnel

kubectl delete -f manifests/envoy-gateway.yaml ; helm uninstall eg -n envoy-gateway-system   # clean up
```

---

## 3. Record results

After each `k6 run`, read these from the k6 summary and fill in `scorecard.md`:
- **http_reqs** rate -> Req/s (throughput — higher is better)
- **http_req_duration** `p(95)` -> p95 latency (and `med` -> p50; lower is better)
- **http_req_failed** rate -> Error rate (should be 0%)

---

## 4. Tear it all down

```bash
kind delete cluster --name bakeoff   # deletes the whole local cluster (and everything in it)
```

Everything was local and disposable — this removes it completely.

---

## Troubleshooting

- **`docker` permission denied** — you skipped `newgrp docker` or didn't log
  out/in after `usermod -aG docker`. Fix: `newgrp docker` (or re-login).
- **`kind create` fails / "no space left on device"** — free up disk (~15 GB)
  and prune Docker: `docker system prune -a` (does not touch data volumes).
- **port-forward target not found** — the service name depends on the Helm
  release name. Run `kubectl get svc -A` and use the actual proxy/controller service.
- **k6 not found after apt install** — open a new shell, or use the snap:
  `sudo snap install k6`.
- **What is `PF=$!`?** — `&` runs the port-forward in the background; `$!` is its
  process id, saved in `PF` so `kill $PF` can stop it after the test.
