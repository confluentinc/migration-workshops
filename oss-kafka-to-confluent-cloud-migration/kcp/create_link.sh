#!/usr/bin/env bash
#
# Send the cluster-link creation request from the bastion, with exactly the payload the
# KCP-generated provisioning instance sends at boot (after kcp/prepare_migration_infra.sh).
# That instance makes a single attempt and only its console log shows the answer, so use
# this to see why a link wasn't created, or to create it.
#
# Usage (on the bastion, after `terraform -chdir=migration-infra apply`):
#   ./kcp/create_link.sh --validate-only   # Confluent Cloud validates the link, creates nothing
#   ./kcp/create_link.sh                   # create the link
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFRA_DIR="${ROOT_DIR}/migration-infra"
TPL="${INFRA_DIR}/external_outbound_cluster_link/create-external-outbound-cluster-link.tpl"

# shellcheck disable=SC1091
source "${ROOT_DIR}/workshop.env"
if [ ! -f "${ROOT_DIR}/target.env" ] || [ ! -f "${TPL}" ]; then
  echo "ERROR: run STEP-2 first: kcp/write_target_env.sh and the migration-infra generation."
  exit 1
fi
# shellcheck disable=SC1091
source "${ROOT_DIR}/target.env"

validate_only=false
[ "${1:-}" = "--validate-only" ] && validate_only=true

# Fill the template's placeholders with the same values Terraform passes the instance. The
# payload holds the SCRAM password, so it goes in a private temp file, not on a command line.
payload_file=$(mktemp)
trap 'rm -f "${payload_file}"' EXIT
python3 - "${TPL}" "${INFRA_DIR}/inputs.auto.tfvars" > "${payload_file}" <<'PY'
import json
import os
import re
import string
import sys

tpl_path, tfvars_path = sys.argv[1], sys.argv[2]
body = re.search(r"--data '(.*?)'", open(tpl_path).read(), re.S).group(1)
tfvars = dict(re.findall(r'^(\w+)\s*=\s*"([^"]*)"', open(tfvars_path).read(), re.M))
rendered = string.Template(body).safe_substitute({
    "source_cluster_id": tfvars["source_cluster_id"],
    "source_cluster_bootstrap_brokers": tfvars["source_cluster_bootstrap_servers"],
    "source_sasl_scram_mechanism": tfvars["source_sasl_scram_mechanism"],
    "source_sasl_scram_username": os.environ["KAFKA_SCRAM_USER"],
    "source_sasl_scram_password": os.environ["KAFKA_SCRAM_PASSWORD"],
})
if "${" in rendered:
    sys.exit(f"ERROR: unfilled placeholder in {tpl_path}; this KCP version's template changed")
json.loads(rendered)
print(rendered)
PY

echo "POST ${CLUSTER_LINK_NAME} (validate_only=${validate_only}) -> ${TARGET_REST_ENDPOINT}"
curl -sS -X POST -u "${CC_API_KEY}:${CC_API_SECRET}" \
  -H "Content-Type: application/json" --data @"${payload_file}" \
  -w '\nHTTP %{http_code}\n' \
  "${TARGET_REST_ENDPOINT}/kafka/v3/clusters/${TARGET_CLUSTER_ID}/links?link_name=${CLUSTER_LINK_NAME}&validate_only=${validate_only}"
