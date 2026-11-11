#!/bin/bash
# health-check grain in blueprints/k8s-compliance.yaml.
#
# A LoadBalancer IP is assigned before the cloud load balancer actually
# routes traffic, so the portal grain can finish while the app is still
# unreachable from outside. This waits until Online Boutique answers on its
# public address, then checks pages that exercise the backend services, so
# the environment only turns Active once the shop really works.
#
# Usage: health-check.sh <base-url> [timeout-seconds]

BASE_URL="${1:?usage: health-check.sh <base-url> [timeout-seconds]}"
BASE_URL="${BASE_URL%/}"
TIMEOUT="${2:-600}"
INTERVAL=10

# 1. External reachability: wait for the frontend's health endpoint.
echo "Waiting up to ${TIMEOUT}s for ${BASE_URL}/_healthz"
waited=0
until [ "$(curl -s --max-time 5 "${BASE_URL}/_healthz")" = "ok" ]; do
  if [ "$waited" -ge "$TIMEOUT" ]; then
    echo "Timed out: ${BASE_URL} is not reachable" >&2
    exit 1
  fi
  sleep "$INTERVAL"
  waited=$((waited + INTERVAL))
done
echo "Reachable after ~${waited}s"

# 2. Application checks. Each page fans out to backend services, so a 200
# means those services answered too.
failed=0
check() {
  local path="$1" expect="$2" what="$3" body
  if body="$(curl -sf --max-time 15 "${BASE_URL}${path}")" && printf '%s' "$body" | grep -q "$expect"; then
    echo "PASS  ${path}  (${what})"
  else
    echo "FAIL  ${path}  (${what})" >&2
    failed=1
  fi
}
check "/"                   "Online Boutique" "home: product catalog, currency, ads, recommendations"
check "/product/OLJCESPC7Z" "Sunglasses"      "product page: product catalog, recommendations"
check "/cart"               "Online Boutique" "cart: cart service and Redis"

if [ "$failed" -ne 0 ]; then
  echo "Online Boutique is reachable but not fully healthy" >&2
  exit 1
fi
echo "Online Boutique is up at ${BASE_URL}"
