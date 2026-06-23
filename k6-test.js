// Load test for the gateway bake-off.
// Run AFTER you have a gateway installed and port-forwarded to localhost:8080.
//
//   k6 run k6-test.js                 # default: http://localhost:8080
//   BASE=http://localhost:8080 k6 run k6-test.js
//
// Record from the summary: http_reqs (req/s), http_req_duration p(95),
// and http_req_failed rate — put them in scorecard.md.

import http from "k6/http";
import { check } from "k6";

export const options = {
  // Ramp to 50 concurrent users, hold, then ramp down.
  stages: [
    { duration: "20s", target: 50 },
    { duration: "1m", target: 50 },
    { duration: "10s", target: 0 },
  ],
  thresholds: {
    http_req_duration: ["p(95)<500"], // 95% of requests under 500ms
    http_req_failed: ["rate<0.01"],   // <1% errors
  },
};

const BASE = __ENV.BASE || "http://localhost:8080";

export default function () {
  const res = http.get(`${BASE}/get`);
  check(res, {
    "status is 200": (r) => r.status === 200,
  });
}
