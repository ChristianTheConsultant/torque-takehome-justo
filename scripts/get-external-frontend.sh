#!/bin/bash
# post-kubernetes-install script for the `portal` grain in
# blueprints/k8s-as-a-service.yaml.
#
# Waits for GCP to give Online Boutique's frontend-external LoadBalancer
# Service a public IP and exports it as the grain output `frontend`. Torque
# only captures exported variables whose names are listed under the script's
# `outputs:` in the blueprint.
#
# Usage: get-external-frontend.sh <namespace> [timeout-seconds]

NAMESPACE="${1:-default}"
TIMEOUT="${2:-600}"
SERVICE=frontend-external
INTERVAL=10

echo "Waiting up to ${TIMEOUT}s for ${SERVICE} in namespace ${NAMESPACE} to get an external IP"
ip=""
waited=0
while [ -z "$ip" ] && [ "$waited" -lt "$TIMEOUT" ]; do
  ip=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  if [ -z "$ip" ]; then
    sleep "$INTERVAL"
    waited=$((waited + INTERVAL))
  fi
done

if [ -z "$ip" ]; then
  echo "Timed out waiting for an external IP on ${SERVICE}" >&2
  kubectl get service "$SERVICE" -n "$NAMESPACE" -o wide >&2
  exit 1
fi

# Wait for the pods too, so the link works as soon as the environment turns
# Active. A slow rollout only warns: the IP is already known.
echo "Waiting for deployments in ${NAMESPACE} to become available"
if ! kubectl wait deployment --all -n "$NAMESPACE" --for=condition=Available --timeout=300s; then
  echo "Warning: not all deployments are available yet" >&2
  kubectl get pods -n "$NAMESPACE" >&2
fi

export frontend="$ip"
echo "frontend=${frontend}"
