#!/bin/bash
# validate-datree grain in blueprints/k8s-compliance.yaml.
#
# Runs a Datree policy check on the Kubernetes manifests before the portal
# grain deploys them, and exits non-zero on any violation so the
# environment stops before deployment.
#
# Datree the company has shut down: get.datree.io (the installer the Torque
# docs use) no longer resolves and its API is gone. The last CLI release is
# still on GitHub and runs fully offline with DATREE_OFFLINE=local, using
# the policy file passed in instead of one from Datree's backend.
#
# Usage: validate-datree.sh <manifest> <policy-file>

set -euo pipefail

MANIFEST="${1:?usage: validate-datree.sh <manifest> <policy-file>}"
POLICY="${2:?usage: validate-datree.sh <manifest> <policy-file>}"

DATREE_VERSION=1.9.19
DATREE_ZIP_SHA256=d6e5b75f4ed16e2df67f3e8ff1f219045ce2410ea109835f46f73ae0e143fa49  # Linux_x86_64

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
echo "Downloading Datree CLI ${DATREE_VERSION}"
curl -fsSL -o "$workdir/datree.zip" \
  "https://github.com/datreeio/datree/releases/download/${DATREE_VERSION}/datree-cli_${DATREE_VERSION}_Linux_x86_64.zip"
if [ "$(sha256_of "$workdir/datree.zip")" != "$DATREE_ZIP_SHA256" ]; then
  echo "Checksum mismatch for the Datree CLI download" >&2
  exit 1
fi
unzip -q -o "$workdir/datree.zip" datree -d "$workdir"

# Must be set before the first datree call: in the default mode the CLI
# first tries to register a token with the (dead) Datree API and fails.
export DATREE_OFFLINE=local

echo "Running Datree policy check on ${MANIFEST} with ${POLICY}"
"$workdir/datree" test "$MANIFEST" \
  --policy-config "$POLICY" \
  --ignore-missing-schemas \
  --no-record \
  --output simple
