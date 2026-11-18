#!/bin/bash
# retry-end grain in blueprints/retry-end-environment.yaml.
#
# Asks Torque to end one environment again when it is in Terminate Failed,
# through the Torque REST API. Uses the normal End (DELETE), never Force End.
# An environment in any other status is left alone, so running this on a
# healthy environment does nothing.
#
# Torque only accepts the request here; the teardown runs after this script
# exits. If it fails again, the environment returns to Terminate Failed.
#
# Usage: retry-end-environment.sh <space> <environment-id> [torque-host]
# The API token is read from TORQUE_TOKEN.

set -euo pipefail

SPACE="${1:?usage: retry-end-environment.sh <space> <environment-id> [torque-host]}"
ENV_ID="${2:?usage: retry-end-environment.sh <space> <environment-id> [torque-host]}"
HOST="${3:-portal.qtorque.io}"
: "${TORQUE_TOKEN:?TORQUE_TOKEN is not set}"

API="https://${HOST}/api/spaces/${SPACE}/environments/${ENV_ID}"
body="$(mktemp)"

# Calls the API and prints the HTTP status. The response body is left in $body.
call() {
  curl -sS -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer ${TORQUE_TOKEN}" "$@"
}

# 1. Only act on an environment that is stuck in Terminate Failed.
status="$(call "${API}")"
if [ "$status" = "404" ]; then
  echo "Environment ${ENV_ID} no longer exists in space '${SPACE}': nothing to do"
  exit 0
fi
if [ "$status" != "200" ]; then
  echo "Reading environment ${ENV_ID} in space '${SPACE}' failed (HTTP ${status}): $(cat "$body")" >&2
  exit 1
fi

env_status="$(jq -r '.details.computed_status // "unknown"' "$body")"
name="$(jq -r '.details.definition.metadata.name // "unnamed"' "$body")"
if [ "$env_status" != "Terminate Failed" ]; then
  echo "SKIP  ${name} (${ENV_ID}) is '${env_status}', not 'Terminate Failed': nothing to do"
  exit 0
fi

# 2. End it again. A 202 means Torque accepted the request.
status="$(call -X DELETE "${API}")"
case "$status" in
  200|202|204)
    echo "END   ${name} (${ENV_ID}): Torque is ending it again; follow the teardown on the Environments page"
    ;;
  404)
    echo "Environment ${ENV_ID} no longer exists: nothing to do"
    ;;
  400)
    if grep -q ENVIRONMENT_STATE_CONFLICT "$body"; then
      echo "SKIP  ${name} (${ENV_ID}) is already terminating"
    else
      echo "FAIL  ${name} (${ENV_ID}): HTTP ${status} $(cat "$body")" >&2
      exit 1
    fi
    ;;
  *)
    echo "FAIL  ${name} (${ENV_ID}): HTTP ${status} $(cat "$body")" >&2
    exit 1
    ;;
esac
