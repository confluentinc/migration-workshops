#!/usr/bin/env bash
#
# Install Confluent for Kubernetes (CFK) on the bastion's k3s cluster and deploy the
# Confluent Gateway in passthrough mode: client SCRAM traffic flows through to the source
# broker on EC2 over SASL_SSL, verified against the workshop CA.
#
# Run this on the bastion during STEP-0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/gateway-manifests"

# shellcheck disable=SC1091
source "${ROOT_DIR}/workshop.env"

echo "============================================="
echo "  Deploying Confluent Gateway (k3s + CFK)"
echo "============================================="

# --- 1. Preflight ------------------------------------------------------------
echo ""
echo "[1/5] Checking k3s and tools..."
for tool in kubectl helm keytool; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' not found. Wait for the bastion setup to finish: cloud-init status --wait"
    exit 1
  fi
done
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: k3s is not reachable. Check: sudo systemctl status k3s"
  exit 1
fi
echo "  k3s is ready. Source broker: ${KAFKA_BOOTSTRAP}"

# --- 2. Install the CFK operator ---------------------------------------------
echo ""
echo "[2/5] Installing Confluent for Kubernetes (CFK) operator..."
helm repo add confluentinc https://packages.confluent.io/helm >/dev/null 2>&1 || true
helm repo update >/dev/null
kubectl create namespace confluent 2>/dev/null || true
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
  --namespace confluent \
  --set namespaced=false \
  --wait --timeout 5m
echo "  CFK operator installed."

# --- 3. Truststore for the source broker -------------------------------------
echo ""
echo "[3/5] Creating the oss-tls truststore from the workshop CA..."
_TMPDIR=$(mktemp -d)
trap 'rm -rf "$_TMPDIR"' EXIT
keytool -importcert -noprompt -alias oss-workshop-ca -file "${CA_CERT_FILE}" \
  -keystore "${_TMPDIR}/truststore.jks" -storetype JKS -storepass changeit >/dev/null
echo "jksPassword=changeit" > "${_TMPDIR}/jksPassword.txt"
kubectl create secret generic oss-tls \
  --from-file=truststore.jks="${_TMPDIR}/truststore.jks" \
  --from-file=jksPassword.txt="${_TMPDIR}/jksPassword.txt" \
  -n confluent 2>/dev/null || kubectl get secret oss-tls -n confluent >/dev/null
echo "  oss-tls secret created."

# --- 4. Deploy the passthrough Gateway ---------------------------------------
echo ""
echo "[4/5] Deploying the Gateway (passthrough to ${KAFKA_BOOTSTRAP})..."
sed "s#__OSS_BOOTSTRAP__#${KAFKA_BOOTSTRAP}#g" \
  "${MANIFESTS_DIR}/gateway-passthrough.yaml" | kubectl apply -f -

for i in $(seq 1 30); do
  if kubectl get pods -n confluent -l app=workshop-gateway --no-headers 2>/dev/null | grep -q .; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Gateway pods were never created. Check the operator logs:"
    echo "  kubectl logs -n confluent -l app=confluent-operator"
    exit 1
  fi
  sleep 10
done
kubectl wait --for=condition=Ready pod -l app=workshop-gateway -n confluent --timeout=300s

# --- 5. Summary --------------------------------------------------------------
echo ""
echo "[5/5] Gateway status:"
kubectl get gateways.platform.confluent.io -n confluent || true
kubectl get pods -n confluent -l app=workshop-gateway || true

echo ""
echo "============================================="
echo "  Gateway deployed: localhost:9595"
echo "============================================="
echo ""
echo "  Next: run the producer and consumer through it (clients/env.gateway)."
echo "============================================="
