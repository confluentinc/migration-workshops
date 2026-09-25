#!/usr/bin/env bash
#
# Inspect the migration on the Enterprise cluster through its private REST endpoint, which
# is only reachable from inside the VPC (run it on the bastion). Uses target.env.
#
# Usage: ./kcp/cc_status.sh link | configs | mirrors | groups
#   link     cluster link state and error, if any
#   configs  the link's security, truststore and consumer-offset settings
#   mirrors  mirror topics with their status and maximum partition lag
#   groups   consumer groups on the destination (orders-consumer-group appears once
#            offsets have synced)
set -euo pipefail

: "${TARGET_REST_ENDPOINT:?Run: source ~/oss-workshop/target.env}"
: "${CLUSTER_LINK_NAME:?Run: source ~/oss-workshop/target.env}"

BASE="${TARGET_REST_ENDPOINT}/kafka/v3/clusters/${TARGET_CLUSTER_ID}"

api() {
  local body
  if ! body=$(curl -sS --fail-with-body -u "${CC_API_KEY}:${CC_API_SECRET}" "${BASE}$1"); then
    echo "Request failed: GET ${BASE}$1" >&2
    [ -n "${body}" ] && echo "${body}" >&2
    exit 1
  fi
  printf '%s' "${body}"
}

case "${1:-link}" in
  link)
    api "/links/${CLUSTER_LINK_NAME}" \
      | jq '{link_name, link_state, link_error, link_error_message, source_cluster_id, topic_names}'
    ;;
  configs)
    api "/links/${CLUSTER_LINK_NAME}/configs" \
      | jq -r '.data[]
          | select(.name | test("^(bootstrap\\.servers|security\\.protocol|sasl\\.mechanism|ssl\\.truststore\\.type|consumer\\.offset\\.)"))
          | "\(.name)=\(.value)"'
    ;;
  mirrors)
    api "/links/${CLUSTER_LINK_NAME}/mirrors" \
      | jq '.data[] | {mirror_topic_name, mirror_status, max_partition_lag: ([.mirror_lags[]?.lag] | max)}'
    ;;
  groups)
    api "/consumer-groups" | jq -r '.data[].consumer_group_id'
    ;;
  *)
    echo "Usage: $0 link | configs | mirrors | groups"
    exit 1
    ;;
esac
