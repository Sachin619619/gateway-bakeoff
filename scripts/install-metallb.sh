#!/usr/bin/env bash
# Install MetalLB in a local kind cluster and create an address pool.
#
# kind does not provide cloud LoadBalancer IPs by default. MetalLB fills that
# local gap so gateway services can be tested with service.type=LoadBalancer.

set -euo pipefail

METALLB_VERSION="${METALLB_VERSION:-v0.14.9}"
KIND_NETWORK="${KIND_NETWORK:-kind}"

echo "Installing MetalLB ${METALLB_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

echo "Waiting for MetalLB controller..."
kubectl -n metallb-system rollout status deploy/controller --timeout=180s

echo "Waiting for MetalLB speaker..."
kubectl -n metallb-system rollout status ds/speaker --timeout=180s

SUBNET="$(
  docker network inspect "${KIND_NETWORK}" --format '{{json .IPAM.Config}}' | python3 -c '
import ipaddress
import json
import sys

configs = json.load(sys.stdin)
for item in configs:
    subnet = item.get("Subnet", "")
    try:
        network = ipaddress.ip_network(subnet, strict=False)
    except ValueError:
        continue
    if network.version == 4:
        print(subnet)
        break
'
)"
if [ -z "${SUBNET}" ]; then
  echo "Could not detect Docker IPv4 network subnet for '${KIND_NETWORK}'." >&2
  exit 1
fi

POOL_RANGE="$(
  python3 - "${SUBNET}" <<'PY'
import ipaddress
import sys

network = ipaddress.ip_network(sys.argv[1], strict=False)
if network.num_addresses < 256:
    raise SystemExit(f"Subnet {network} is too small for the default MetalLB range")

start = ipaddress.ip_address(int(network.network_address) + 200)
end = ipaddress.ip_address(min(int(network.network_address) + 250, int(network.broadcast_address) - 1))
print(f"{start}-{end}")
PY
)"

echo "Using MetalLB address pool: ${POOL_RANGE}"

cat <<YAML | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: local-pool
  namespace: metallb-system
spec:
  addresses:
    - ${POOL_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: local-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - local-pool
YAML

echo "MetalLB is ready for local LoadBalancer services."
