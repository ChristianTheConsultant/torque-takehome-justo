#!/bin/bash
# validate-kubescape grain in blueprints/k8s-compliance.yaml.
#
# Scans the Kubernetes manifests with Kubescape against a compliance
# framework before the portal grain deploys them. Kubescape exits non-zero
# when the compliance score is below the threshold, which fails the grain
# and stops the environment before deployment.
#
# Usage: validate-kubescape.sh <manifest> <framework> <compliance-threshold>

set -euo pipefail

MANIFEST="${1:?usage: validate-kubescape.sh <manifest> <framework> <compliance-threshold>}"
FRAMEWORK="${2:?usage: validate-kubescape.sh <manifest> <framework> <compliance-threshold>}"
THRESHOLD="${3:?usage: validate-kubescape.sh <manifest> <framework> <compliance-threshold>}"

KUBESCAPE_VERSION=4.0.16
KUBESCAPE_SHA256=fcf172f0d1fb5683379586bcf8875091da4d0d815bd304f8098d58be65ecab0d  # linux_amd64

sha256_of() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
  fi
}

if [ "$(uname -m)" != "x86_64" ]; then
  echo "Only x86_64 runners are supported (got $(uname -m))" >&2
  exit 1
fi

workdir="$(mktemp -d)"
echo "Downloading Kubescape ${KUBESCAPE_VERSION}"
curl -fsSL -o "$workdir/kubescape" \
  "https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE_VERSION}/kubescape_${KUBESCAPE_VERSION}_linux_amd64"
if [ "$(sha256_of "$workdir/kubescape")" != "$KUBESCAPE_SHA256" ]; then
  echo "Checksum mismatch for the Kubescape download" >&2
  exit 1
fi
chmod +x "$workdir/kubescape"

echo "Scanning ${MANIFEST} against the ${FRAMEWORK} framework (minimum compliance score: ${THRESHOLD}%)"
"$workdir/kubescape" scan framework "$FRAMEWORK" "$MANIFEST" \
  --compliance-threshold "$THRESHOLD" \
  --keep-local
