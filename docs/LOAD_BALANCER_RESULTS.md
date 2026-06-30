# LoadBalancer Results

This file contains only the LoadBalancer-mode test results. Use this when you
want to discuss the MetalLB / `service.type=LoadBalancer` path without opening
the full bake-off result file.

## Test Setup

| Item | Value |
|------|-------|
| Test date | 2026-06-29 |
| Cluster | local kind cluster, single node |
| LoadBalancer provider | MetalLB |
| MetalLB pool | `172.19.0.200-172.19.0.250` |
| Assigned LoadBalancer IP | `172.19.0.200` |
| Backend | `httpbin`, 2 replicas |
| Load test | k6, 50 virtual users, about 90 seconds |

Important local note: on Docker Desktop for macOS, the MetalLB Docker-network IP
was reachable from inside the kind/Docker network, but not directly from the
macOS host. Because of that, the benchmark was run as a k6 pod inside the
cluster against the MetalLB IP.

## Interaction Diagram

![Local LoadBalancer request flow](diagrams/load-balancer-sequence.png)

## Result Table

| Gateway | LB IP | HTTP via LB IP | HTTPS via LB IP | Req/s | p50 | p95 | Errors |
|---------|-------|----------------|-----------------|-------|-----|-----|--------|
| HAProxy | 172.19.0.200 | Yes | Yes | 24,375 | 1.02 ms | 5.06 ms | 0% |
| NGINX | 172.19.0.200 | Yes | Yes | 24,093 | 1.18 ms | 4.69 ms | 0% |
| Traefik | 172.19.0.200 | Yes | Yes | 24,069 | 1.26 ms | 4.44 ms | 0% |
| Kong | 172.19.0.200 | Yes | Yes | 21,709 | 1.38 ms | 4.86 ms | 0% |
| Envoy Gateway | 172.19.0.200 | Yes | Yes | 18,708 | 1.50 ms | 5.99 ms | 0% |

## Verification Summary

- MetalLB assigned `172.19.0.200`.
- All five gateways served HTTP through the LoadBalancer IP.
- All five gateways served HTTPS through the LoadBalancer IP.
- All five gateways completed the k6 run with `0%` errors.
- NGINX, Traefik, and Kong forwarded `X-Forwarded-For`,
  `X-Forwarded-Host`, `X-Forwarded-Port`, and `X-Forwarded-Proto`.
- HAProxy forwarded `X-Forwarded-For` and `X-Forwarded-Proto`.
- Envoy Gateway forwarded `X-Forwarded-For` and `X-Forwarded-Proto`.

## Interpretation

HAProxy had the highest raw throughput in this LoadBalancer-mode test. NGINX
and Traefik were very close behind it. Kong and Envoy Gateway were slower in
raw throughput, but still completed the test with low latency and no errors.

These numbers are not direct replacements for the earlier `kubectl
port-forward` numbers. This test avoids the local port-forward bottleneck by
running k6 inside the cluster network, so the throughput is much higher.

## Commands Used

Install MetalLB:

```bash
bash scripts/install-metallb.sh
```

Verify a gateway LoadBalancer service:

```bash
bash scripts/verify-loadbalancer.sh <namespace> <service-name>
```

Run k6 from inside the cluster network:

```bash
kubectl create configmap k6-script --from-file=k6-test.js --dry-run=client -o yaml | kubectl apply -f -

kubectl run k6-lb --restart=Never --image=grafana/k6:latest \
  --env=BASE=http://172.19.0.200:80 \
  --overrides='{"spec":{"containers":[{"name":"k6-lb","image":"grafana/k6:latest","args":["run","/scripts/k6-test.js"],"env":[{"name":"BASE","value":"http://172.19.0.200:80"}],"volumeMounts":[{"name":"script","mountPath":"/scripts"}]}],"volumes":[{"name":"script","configMap":{"name":"k6-script"}}]}}'

kubectl logs -f pod/k6-lb
```

Clean up the local cluster after testing:

```bash
kind delete cluster --name bakeoff
```
