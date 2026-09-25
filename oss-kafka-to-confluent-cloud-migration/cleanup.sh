#!/usr/bin/env bash
#
# Tear down what the workshop created FROM THE BASTION, in dependency order:
#   1. the producer/consumer
#   2. the Gateway (CFK, k3s namespace) and Vault
#   3. migrate_topics/   mirror topics                          (KCP-generated)
#   4. migration-infra/  cluster link path: NLB, endpoint service,
#                        Confluent egress gateway + access point (KCP-generated)
#   5. target_infra/     Enterprise cluster, environment, ingress PrivateLink (KCP-generated)
#
# Then destroy the AWS source environment from your laptop: terraform destroy in terraform/.
# The KCP-generated resources live inside that VPC, so they must go first.
#
# Needs the same credentials as STEP-2: AWS credentials and TF_VAR_confluent_cloud_api_key /
# TF_VAR_confluent_cloud_api_secret exported in this shell.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Set by any step that cannot confirm teardown of a billable resource; the script then
# exits non-zero instead of reporting success.
CLEANUP_FAILED=0

# shellcheck disable=SC1091
[ -f "${ROOT_DIR}/workshop.env" ] && source "${ROOT_DIR}/workshop.env"
# shellcheck disable=SC1091
[ -f "${ROOT_DIR}/target.env" ] && source "${ROOT_DIR}/target.env"

echo "============================================="
echo "  OSS -> Confluent Cloud Workshop Cleanup"
echo "============================================="

missing=()
[ -z "${TF_VAR_confluent_cloud_api_key:-}" ] && missing+=("TF_VAR_confluent_cloud_api_key")
[ -z "${TF_VAR_confluent_cloud_api_secret:-}" ] && missing+=("TF_VAR_confluent_cloud_api_secret")
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  missing+=("AWS credentials (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN)")
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo ""
  echo "ERROR: export these first (the same values as in STEP-2):"
  printf '  - %s\n' "${missing[@]}"
  exit 1
fi

# --- 1. Clients -------------------------------------------------------------
echo ""
echo "[1/5] Stopping producer/consumer..."
pkill -f "python3 .*orders_producer.py" 2>/dev/null || true
pkill -f "python3 .*orders_consumer.py" 2>/dev/null || true
rm -f "${ROOT_DIR}/clients/"*.pid 2>/dev/null || true
echo "  Done."

# --- 2. Gateway and Vault ----------------------------------------------------
echo ""
echo "[2/5] Removing the Gateway, CFK and Vault..."
if kubectl cluster-info >/dev/null 2>&1; then
  kubectl delete gateways.platform.confluent.io workshop-gateway -n confluent --ignore-not-found --wait=true || true
  helm uninstall confluent-operator -n confluent 2>/dev/null || true
  kubectl delete namespace confluent --ignore-not-found || true
fi
pkill -f "vault server -dev.*workshop-token" 2>/dev/null || true
rm -rf "${ROOT_DIR}/gateway/rendered-crs"
echo "  Done."

# Destroy one KCP-generated Terraform directory. Returns non-zero if resources remain.
destroy_dir() {
  local dir="$1"
  if [ ! -f "${dir}/terraform.tfstate" ]; then
    echo "  No Terraform state in ${dir} - skipping."
    return 0
  fi
  # target-infra defaults to prevent_destroy = true unless generated with
  # --prevent-destroy=false (as STEP-2 does); lift it so a missed flag can't strand the cluster.
  grep -rlE 'prevent_destroy[[:space:]]*=[[:space:]]*true' "${dir}" --include='*.tf' 2>/dev/null \
    | xargs -r sed -i -E 's/prevent_destroy[[:space:]]*=[[:space:]]*true/prevent_destroy = false/'
  terraform -chdir="${dir}" init -input=false >/dev/null || return 1
  terraform -chdir="${dir}" destroy -auto-approve -input=false || true
  local remaining
  remaining=$(terraform -chdir="${dir}" state list 2>/dev/null | grep -c . || true)
  if [ "${remaining}" != "0" ]; then
    echo "  ERROR: ${remaining} resource(s) still in ${dir}'s state."
    return 1
  fi
  echo "  Destroyed everything in ${dir}."
}

# --- 3. Mirror topics --------------------------------------------------------
echo ""
echo "[3/5] Destroying the mirror topics (migrate_topics/)..."
# Not billable on their own: deleting the cluster in step 5 removes them regardless.
destroy_dir "${ROOT_DIR}/migrate_topics" || \
  echo "  WARNING: continuing; the topics are deleted with the cluster in step 5."

# --- 4. Migration infrastructure ---------------------------------------------
echo ""
echo "[4/5] Destroying the cluster link path (migration-infra/)..."
destroy_dir "${ROOT_DIR}/migration-infra" || CLEANUP_FAILED=1

# --- 5. Target infrastructure ------------------------------------------------
echo ""
echo "[5/5] Destroying the Enterprise cluster, environment and PrivateLink (target_infra/)..."
destroy_dir "${ROOT_DIR}/target_infra" || CLEANUP_FAILED=1

echo ""
echo "============================================="
if [ "${CLEANUP_FAILED}" -eq 0 ]; then
  echo "  Bastion cleanup complete."
  echo "============================================="
  echo ""
  echo "  Next, on your laptop:  terraform -chdir=terraform destroy"
  echo "  Then confirm in the Confluent Cloud Console that the workshop environment is gone."
  echo "============================================="
else
  echo "  Cleanup INCOMPLETE - billable resources may remain!"
  echo "============================================="
  echo ""
  echo "  The Enterprise cluster, PrivateLink endpoints and NLB bill hourly. Fix the error"
  echo "  above and re-run ./cleanup.sh (it is safe to re-run), or delete the workshop"
  echo "  environment in the Confluent Cloud Console. Destroy terraform/ from your laptop"
  echo "  only after this succeeds: the VPC cannot be deleted while these resources exist."
  echo "============================================="
  exit 1
fi
