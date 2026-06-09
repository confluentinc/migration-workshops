#!/bin/bash

# Workshop cleanup script - removes KCP deletion protections and destroys all resources
# Run this on the bastion host to tear down all KCP-provisioned Terraform resources.

set -uo pipefail

DIRS_ORDERED=(
  "$HOME/migrate_topics"
  "$HOME/migrate_schemas"
  "$HOME/migrate_acls"
  "$HOME/migrate_connectors"
  "$HOME/migration_infra"
  "$HOME/target_infra"
)

declare -A RESULTS

# --- Remove prevent_destroy from Terraform files ---

remove_prevent_destroy() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    local tf_files
    tf_files=$(find "$dir" -maxdepth 1 -name '*.tf' -type f)
    if [[ -n "$tf_files" ]]; then
      echo "  Removing prevent_destroy in $dir..."
      sed -i 's/prevent_destroy\s*=\s*true/prevent_destroy = false/g' "$dir"/*.tf
    fi
  fi
}

echo "============================================="
echo "Workshop Cleanup - Destroying KCP Resources"
echo "============================================="
echo ""

# --- Step 0: Clean up Gateway and Kubernetes resources ---

echo "Step 0: Cleaning up Gateway resources..."
if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null 2>&1; then
  echo "  Stopping producer/consumer..."
  pkill -f "orders_producer.py" 2>/dev/null || true
  pkill -f "orders_consumer.py" 2>/dev/null || true

  echo "  Removing Gateway resources..."
  kubectl delete gateway workshop-gateway -n confluent 2>/dev/null || true
  kubectl delete secrets msk-tls cc-tls vault-config scram-admin-credentials plain-jaas -n confluent 2>/dev/null || true

  echo "  Uninstalling CFK operator..."
  helm uninstall confluent-operator -n confluent 2>/dev/null || true
  kubectl delete namespace confluent 2>/dev/null || true

  echo "  Stopping Vault..."
  pkill -f "vault server" 2>/dev/null || true

  echo "  Cleaning up rendered CRs..."
  rm -rf "$HOME/gateway-migration-crs" 2>/dev/null || true

  echo "  Gateway cleanup complete."
else
  echo "  SKIPPED (k3s not running or kubectl not found)"
fi
echo ""

echo "Step 1: Removing prevent_destroy protections..."
remove_prevent_destroy "$HOME/target_infra"
remove_prevent_destroy "$HOME/migration_infra"
echo ""

# --- Check for required credentials for migration_infra ---

if [[ -d "$HOME/migration_infra" ]]; then
  missing_vars=()
  [[ -z "${TF_VAR_confluent_cloud_api_key:-}" ]] && missing_vars+=("TF_VAR_confluent_cloud_api_key")
  [[ -z "${TF_VAR_confluent_cloud_api_secret:-}" ]] && missing_vars+=("TF_VAR_confluent_cloud_api_secret")
  [[ -z "${TF_VAR_msk_username:-}" ]] && missing_vars+=("TF_VAR_msk_username")
  [[ -z "${TF_VAR_msk_password:-}" ]] && missing_vars+=("TF_VAR_msk_password")

  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "migration_infra requires credentials. The following env vars are not set:"
    for v in "${missing_vars[@]}"; do
      echo "  - $v"
    done
    echo ""
    echo "Please export them before running this script, or enter them now."

    for v in "${missing_vars[@]}"; do
      read -rp "  $v: " value
      export "$v=$value"
    done
    echo ""
  fi
fi

# --- Destroy resources in dependency order ---

echo "Step 2: Destroying Terraform resources..."
echo ""

for dir in "${DIRS_ORDERED[@]}"; do
  name=$(basename "$dir")

  if [[ ! -d "$dir" ]]; then
    echo "[$name] SKIPPED (directory not found)"
    RESULTS[$name]="skipped"
    continue
  fi

  echo "[$name] Destroying..."

  (
    cd "$dir"
    terraform init -input=false -no-color > /dev/null 2>&1
  )
  init_rc=$?

  if [[ $init_rc -ne 0 ]]; then
    echo "[$name] FAILED (terraform init failed)"
    RESULTS[$name]="failed"
    continue
  fi

  set +e
  (cd "$dir" && terraform destroy -auto-approve -input=false -no-color 2>&1) | tail -5
  destroy_rc=${PIPESTATUS[0]}
  set -e

  if [[ $destroy_rc -eq 0 ]]; then
    echo "[$name] DESTROYED"
    RESULTS[$name]="destroyed"
  else
    echo "[$name] FAILED (terraform destroy exited with $destroy_rc)"
    RESULTS[$name]="failed"
  fi

  echo ""
done

# --- Summary ---

echo "============================================="
echo "Cleanup Summary"
echo "============================================="

for dir in "${DIRS_ORDERED[@]}"; do
  name=$(basename "$dir")
  status="${RESULTS[$name]}"
  case "$status" in
    destroyed) icon="OK" ;;
    skipped)   icon="--" ;;
    failed)    icon="!!" ;;
  esac
  printf "  [%s] %s\n" "$icon" "$name"
done

echo ""

# Check if any failed
has_failure=false
for dir in "${DIRS_ORDERED[@]}"; do
  name=$(basename "$dir")
  if [[ "${RESULTS[$name]}" == "failed" ]]; then
    has_failure=true
    break
  fi
done

if $has_failure; then
  echo "Some resources failed to destroy. Check the output above for details."
  echo "You may need to manually clean up remaining resources in the Confluent Cloud console."
  exit 1
else
  echo "All resources cleaned up successfully."
  exit 0
fi
