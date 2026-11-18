#!/bin/bash
# end-all-environments grain in blueprints/end-all-environments.yaml.
#
# Ends every running (Active or Active With Error) environment in a Torque
# space through the Torque REST API. Skipped:
#   - workflow runs, including the one executing this script
#   - environments with termination protection, which Torque refuses to end
#
# The ids are collected before anything is ended, because ending
# environments changes the list being paged through.
#
# Usage: end-all-environments.sh <space> [torque-host]
# The API token is read from TORQUE_TOKEN.

set -euo pipefail

SPACE="${1:?usage: end-all-environments.sh <space> [torque-host]}"
HOST="${2:-portal.qtorque.io}"
: "${TORQUE_TOKEN:?TORQUE_TOKEN is not set}"

API="https://${HOST}/api/spaces/${SPACE}"
PAGE_SIZE=50
body="$(mktemp)"

# Calls the API and prints the HTTP status. The response body is left in $body.
call() {
  curl -sS -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer ${TORQUE_TOKEN}" "$@"
}

# 1. Collect the running environments.
targets=()
skip=0
while :; do
  status="$(call "${API}/environments/v2?status=Active&status=Active%20With%20Error&paging_info.skip=${skip}&paging_info.take=${PAGE_SIZE}")"
  if [ "$status" != "200" ]; then
    echo "Listing environments in space '${SPACE}' failed (HTTP ${status}): $(cat "$body")" >&2
    exit 1
  fi

  while IFS=$'\t' read -r id protected name owner; do
    if [ "$protected" = "true" ]; then
      echo "SKIP  ${name} (${id}, ${owner}): termination protection is on"
    else
      targets+=("${id}"$'\t'"${name}"$'\t'"${owner}")
    fi
  done < <(jq -r '.environment_list[]
    | select(.is_workflow != true)
    | [.id,
       (.termination_protection_enabled == true | tostring),
       (.details.definition.metadata.name // "unnamed"),
       (.owner.email // "no owner")]
    | @tsv' "$body")

  page_count="$(jq '.environment_list | length' "$body")"
  full_count="$(jq '.paging_info.full_count // 0' "$body")"
  skip=$((skip + PAGE_SIZE))
  if [ "$page_count" -eq 0 ] || [ "$skip" -ge "$full_count" ]; then
    break
  fi
done

if [ "${#targets[@]}" -eq 0 ]; then
  echo "No running environments to end in space '${SPACE}'"
  exit 0
fi

# 2. End them. A 202 means Torque accepted the request; teardown continues
# in the background after this workflow finishes.
echo "Ending ${#targets[@]} environment(s) in space '${SPACE}'"
failed=0
for target in "${targets[@]}"; do
  IFS=$'\t' read -r id name owner <<<"$target"
  status="$(call -X DELETE "${API}/environments/${id}")"
  if [ "$status" = "202" ]; then
    echo "END   ${name} (${id}, ${owner})"
  else
    echo "FAIL  ${name} (${id}, ${owner}): HTTP ${status} $(cat "$body")" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "Some environments could not be ended" >&2
  exit 1
fi
echo "All running environments in space '${SPACE}' are ending"
