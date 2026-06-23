# Gateway Bake-off — Scorecard

Fill this in as you test each gateway locally. Performance numbers come from
`k6 run k6-test.js`; feature columns from the manual checks in the README.

> Azure Application Gateway is **not** in this bake-off — it is a cloud-only
> managed service and cannot run locally.

## Performance (measured — k6, 50 VUs / ~90s, local kind cluster, 2026-06-23)

Ranked by throughput. All gateways: **0% errors** (every request succeeded).

| Rank | Gateway        | Req/s | p50 latency | p95 latency | Error rate |
|------|----------------|-------|-------------|-------------|------------|
| 1    | HAProxy        | 6,665 | 5.5 ms      | 12.2 ms     | 0%         |
| 2    | Traefik        | 5,923 | 6.3 ms      | 13.4 ms     | 0%         |
| 3    | NGINX Ingress  | 5,326 | 6.7 ms      | 15.9 ms     | 0%         |
| 4    | Kong           | 5,123 | 7.0 ms      | 17.1 ms     | 0%         |
| 5    | Envoy Gateway  | 4,789 | 7.2 ms      | 18.4 ms     | 0%         |

> Caveats: single-node kind cluster on a laptop, accessed via `kubectl
> port-forward` (itself a throughput bottleneck), simple `GET /get` (raw L7
> proxying — does not exercise WAF/auth/plugins). Treat numbers as **relative**,
> not production capacity. Relative order matches each tool's known profile.

## Capabilities (✅ / ⚠️ / ❌)

| Capability            | NGINX | Traefik | HAProxy | Kong | Envoy |
|-----------------------|-------|---------|---------|------|-------|
| L7 routing            |       |         |         |      |       |
| SSL termination       |       |         |         |      |       |
| WAF (block a bad req) |       |         |         |      |       |
| Rate limiting         |       |         |         |      |       |
| Authentication        |       |         |         |      |       |
| API-gateway features  |       |         |         |      |       |
| Setup effort (1–5)    |       |         |         |      |       |

## Decision

- **Overall pick (best balance): NGINX Ingress (+ ModSecurity WAF)** — mid-pack
  throughput but rock-stable, most mature, biggest ecosystem, built-in WAF path,
  K8s-native. Safe default you rarely regret.
- **If raw performance is #1: HAProxy** — clearly fastest (6,665 req/s) and most
  consistent (lowest p95, max latency only 62 ms).
- **If you need API-gateway features (auth/keys/plugins/portal): Kong** — a small
  raw-throughput tax is the cost of the extra machinery; worth it when you need it.
- **Honorable mentions:** Traefik (great perf + best DX), Envoy Gateway
  (future-proof on Gateway API, but newest/slowest here).
- **Key finding:** all five were stable with 0% errors and sub-20 ms p95, so at
  this scale **operational fit + features matter more than the raw throughput gap.**
