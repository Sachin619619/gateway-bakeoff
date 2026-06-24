# Running the Bake-off on Ubuntu — Every Command

Step-by-step, copy-paste guide to run the full gateway bake-off on an Ubuntu
machine. Everything runs locally; nothing is exposed to the internet.

> Need ~15 GB free disk — the cluster + 5 gateway images need room.

---

## 0. Install everything (one-time)

### Docker
```bash
sudo apt-get update
sudo apt-get install -y docker.io curl
sudo systemctl enable --now docker
sudo usermod -aG docker $USER     # run docker without sudo
newgrp docker                     # apply group now (or log out & back in)
docker info >/dev/null && echo "Docker OK"
```

### kind (Kubernetes-in-Docker)
```bash
KIND_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep tag_name | cut -d '"' -f4)
curl -Lo ./kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-amd64"
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

### kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

### helm
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### k6
```bash
sudo apt-get install -y gnupg
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install -y k6
```

### Verify
```bash
docker --version && kind version && kubectl version --client && helm version && k6 version
```

---

## 1. Create the cluster + deploy the sample app (once)

```bash
cd gateway-bakeoff
kind create cluster --name bakeoff --wait 120s
kubectl apply -f manifests/httpbin.yaml
kubectl rollout status deploy/httpbin
```

---

## 2. Test each gateway (run one block, record results, move to next)

> On Ubuntu, `sed -i` needs **no** `''` (unlike macOS). Each block is
> self-contained: install -> route -> port-forward (background) -> load test ->
> clean up. After each `k6 run`, copy the numbers into `scorecard.md`.

### 2a. NGINX Ingress
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=ClusterIP --set controller.admissionWebhooks.enabled=false
kubectl -n ingress-nginx rollout status deploy/nginx-ingress-nginx-controller --timeout=150s

sed -i 's/ingressClassName: .*/ingressClassName: nginx/' manifests/ingress.yaml
kubectl apply -f manifests/ingress.yaml

kubectl -n ingress-nginx port-forward svc/nginx-ingress-nginx-controller 8080:80 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
curl -s localhost:8080/get | head -3
k6 run k6-test.js
kill $PF

kubectl delete -f manifests/ingress.yaml ; helm uninstall nginx -n ingress-nginx
```

### 2b. Traefik
```bash
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace --set service.type=ClusterIP
kubectl -n traefik rollout status deploy/traefik --timeout=150s

sed -i 's/ingressClassName: .*/ingressClassName: traefik/' manifests/ingress.yaml
kubectl apply -f manifests/ingress.yaml

kubectl -n traefik port-forward svc/traefik 8080:80 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
curl -s localhost:8080/get | head -3
k6 run k6-test.js
kill $PF

kubectl delete -f manifests/ingress.yaml ; helm uninstall traefik -n traefik
```

### 2c. HAProxy
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts && helm repo update
helm install haproxy haproxytech/kubernetes-ingress -n haproxy --create-namespace \
  --set controller.service.type=ClusterIP
kubectl -n haproxy rollout status deploy/haproxy-kubernetes-ingress --timeout=150s

sed -i 's/ingressClassName: .*/ingressClassName: haproxy/' manifests/ingress.yaml
kubectl apply -f manifests/ingress.yaml

kubectl -n haproxy port-forward svc/haproxy-kubernetes-ingress 8080:80 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
curl -s localhost:8080/get | head -3
k6 run k6-test.js
kill $PF

kubectl delete -f manifests/ingress.yaml ; helm uninstall haproxy -n haproxy
```

### 2d. Kong
```bash
helm repo add kong https://charts.konghq.com && helm repo update
helm install kong kong/kong -n kong --create-namespace --set proxy.type=ClusterIP
kubectl -n kong rollout status deploy/kong-kong --timeout=180s

sed -i 's/ingressClassName: .*/ingressClassName: kong/' manifests/ingress.yaml
kubectl apply -f manifests/ingress.yaml

kubectl -n kong port-forward svc/kong-kong-proxy 8080:80 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
curl -s localhost:8080/get | head -3
k6 run k6-test.js
kill $PF

kubectl delete -f manifests/ingress.yaml ; helm uninstall kong -n kong
```

### 2e. Envoy Gateway (Gateway API, not Ingress)
```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm -n envoy-gateway-system --create-namespace
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s

kubectl apply -f manifests/envoy-gateway.yaml
sleep 10
SVC=$(kubectl -n envoy-gateway-system get svc -o name | grep envoy-default-eg)
kubectl -n envoy-gateway-system port-forward "$SVC" 8080:80 >/tmp/pf.log 2>&1 &
PF=$!; sleep 3
curl -s localhost:8080/get | head -3
k6 run k6-test.js
kill $PF

kubectl delete -f manifests/envoy-gateway.yaml ; helm uninstall eg -n envoy-gateway-system
```

---

## 3. Record results

After each `k6 run`, take from the summary and fill in `scorecard.md`:
- **http_reqs** rate -> Req/s
- **http_req_duration** `p(95)` (and `med` for p50)
- **http_req_failed** rate -> Error rate

---

## 4. Tear it all down

```bash
kind delete cluster --name bakeoff
```

Everything was local and disposable — this removes it completely.

---

## Troubleshooting

- **`docker` permission denied** — you skipped `newgrp docker` or didn't log
  out/in after `usermod -aG docker`. Fix: `newgrp docker` (or re-login).
- **`kind create` fails / "no space left on device"** — free up disk (~15 GB)
  and prune Docker: `docker system prune -a` (does not touch volumes).
- **port-forward target not found** — service name depends on the Helm release.
  Run `kubectl get svc -A` and use the actual proxy/controller service.
- **k6 not found after apt install** — open a new shell, or use the snap:
  `sudo snap install k6`.
