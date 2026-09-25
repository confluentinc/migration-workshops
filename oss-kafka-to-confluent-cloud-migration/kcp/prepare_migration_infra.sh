#!/usr/bin/env bash
#
# Fill in what KCP (as of v0.9.2) cannot know about a self-managed (Apache Kafka) source
# before you apply the Type 2 (external outbound cluster link) Terraform it generated:
#
#   1. Broker network details. For Apache Kafka sources KCP leaves each broker's subnet_id
#      and ip empty, and names the broker "kafka-broker-0", which overflows AWS's
#      32-character limit on the NLB and target-group names derived from it. This writes
#      workshop-brokers.auto.tfvars with broker id "1" (the broker's node.id), its subnet
#      and its private IP. Terraform loads *.auto.tfvars files in lexical order, so it
#      overrides aws_kafka_brokers from KCP's inputs.auto.tfvars.
#
#   2. Cluster link configuration. KCP's link-creation script assumes the broker presents a
#      publicly trusted certificate (true for MSK) and does not sync consumer offsets. This
#      adds the workshop CA as the link's PEM truststore and enables consumer-offset sync
#      for orders-consumer-group every 5s, so the consumer resumes at its committed position
#      after the cutover (kcp/gateway-migration.yaml drains one sync before pausing it).
#
# Usage (on the bastion, from the workshop root, after `kcp create-asset migration-infra`):
#   ./kcp/prepare_migration_infra.sh [migration-infra-dir]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INFRA_DIR="${1:-${ROOT_DIR}/migration-infra}"
TPL="${INFRA_DIR}/external_outbound_cluster_link/create-external-outbound-cluster-link.tpl"

# shellcheck disable=SC1091
source "${ROOT_DIR}/workshop.env"

if [ ! -f "${TPL}" ]; then
  echo "ERROR: ${TPL} not found."
  echo "  Generate the Type 2 assets first: kcp create-asset migration-infra --type 2 ... (STEP-2)."
  exit 1
fi

cat > "${INFRA_DIR}/workshop-brokers.auto.tfvars" <<EOF
# Written by kcp/prepare_migration_infra.sh; overrides aws_kafka_brokers from
# inputs.auto.tfvars (Terraform loads *.auto.tfvars files in lexical order).
aws_kafka_brokers = [{
  id        = "1"
  subnet_id = "${KAFKA_BROKER_SUBNET_ID}"
  endpoints = [{
    host = "${KAFKA_BROKER_HOST}"
    port = ${KAFKA_BROKER_PORT}
    ip   = "${KAFKA_BROKER_IP}"
  }]
}]
EOF
echo "Wrote ${INFRA_DIR}/workshop-brokers.auto.tfvars"
echo "  broker 1: ${KAFKA_BROKER_HOST}:${KAFKA_BROKER_PORT} -> ${KAFKA_BROKER_IP} in ${KAFKA_BROKER_SUBNET_ID}"

python3 - "${TPL}" "${CA_CERT_FILE}" <<'PY'
import json
import re
import sys

tpl_path, ca_path = sys.argv[1], sys.argv[2]
with open(tpl_path) as f:
    text = f.read()

# The link is created by `curl ... --data '<json>'`; the JSON holds Terraform template
# interpolations (${...}) inside string values, so it parses as-is.
match = re.search(r"--data '(.*?)'", text, re.S)
if not match:
    sys.exit(f"ERROR: could not find the cluster link payload in {tpl_path}")
payload = json.loads(match.group(1))

with open(ca_path) as f:
    ca_pem = f.read().strip()

extra = {
    "ssl.truststore.type": "PEM",
    "ssl.truststore.certificates": ca_pem,
    "consumer.offset.sync.enable": "true",
    "consumer.offset.sync.ms": "5000",
    "consumer.offset.group.filters": json.dumps({"groupFilters": [
        {"name": "orders-consumer-group", "patternType": "LITERAL", "filterType": "INCLUDE"},
    ]}),
}
payload["configs"] = [c for c in payload["configs"] if c["name"] not in extra]
payload["configs"] += [{"name": name, "value": value} for name, value in extra.items()]

rendered = json.dumps(payload, indent=2)
# The payload sits inside single quotes in a Terraform template: it must not contain a
# single quote or start a template directive.
if "'" in rendered or "%{" in rendered:
    sys.exit("ERROR: the new link payload contains characters the template cannot hold")

with open(tpl_path, "w") as f:
    f.write(text[:match.start(1)] + rendered + text[match.end(1):])
print(f"Updated {tpl_path}")
print("  link config += " + ", ".join(extra))
PY
