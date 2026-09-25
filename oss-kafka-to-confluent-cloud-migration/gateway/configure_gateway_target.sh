#!/usr/bin/env bash
#
# Configure the Gateway with the Confluent Cloud target for the cutover:
#   1. Starts Vault (dev mode) on the bastion for the credential mapping
#   2. Stores the SCRAM -> Confluent Cloud API key mapping in Vault
#   3. Creates the secrets the Gateway needs (CC truststore, Vault config, SCRAM admin, JAAS)
#   4. Updates the Gateway to its init state (OSS + Confluent Cloud streaming domains)
#   5. Registers the SCRAM user through the Gateway's registration route
#   6. Renders the switchover CR for `kcp migration` (KCP derives the fence itself, from the
#      live Gateway, so there is no fenced CR)
#
# Run this on the bastion in STEP-2, after kcp/write_target_env.sh has written target.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/gateway-manifests"
RENDERED_DIR="${SCRIPT_DIR}/rendered-crs"

# shellcheck disable=SC1091
source "${ROOT_DIR}/workshop.env"
if [ ! -f "${ROOT_DIR}/target.env" ]; then
  echo "ERROR: ${ROOT_DIR}/target.env not found. Run kcp/write_target_env.sh first (STEP-2)."
  exit 1
fi
# shellcheck disable=SC1091
source "${ROOT_DIR}/target.env"

render() {
  sed -e "s#__OSS_BOOTSTRAP__#${KAFKA_BOOTSTRAP}#g" \
      -e "s#__CC_BOOTSTRAP_SERVERS__#${CC_BOOTSTRAP_SERVERS}#g" \
      "$1"
}

echo "============================================="
echo "  Configuring Gateway for Cutover"
echo "============================================="

# --- 1. Verify the Gateway ---------------------------------------------------
echo ""
echo "[1/7] Verifying the Gateway is running..."
if ! kubectl get gateways.platform.confluent.io workshop-gateway -n confluent >/dev/null 2>&1; then
  echo "ERROR: Gateway 'workshop-gateway' not found. Run gateway/setup_gateway.sh first."
  exit 1
fi
echo "  Gateway is running."

# --- 2. Start Vault (dev mode) and store the credential mapping --------------
echo ""
echo "[2/7] Starting Vault (dev mode) and storing the credential mapping..."
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="workshop-token"
if ! vault status >/dev/null 2>&1; then
  # Listens on all interfaces so the Gateway pods can reach it via the node IP. The
  # bastion's security group only admits SSH, so Vault is not reachable from outside.
  nohup vault server -dev \
    -dev-root-token-id="workshop-token" \
    -dev-listen-address="0.0.0.0:8200" \
    > /tmp/workshop-vault.log 2>&1 &
  sleep 3
fi
vault status >/dev/null
vault kv put "secret/${KAFKA_SCRAM_USER}" value="${CC_API_KEY}/${CC_API_SECRET}" >/dev/null
echo "  Mapped ${KAFKA_SCRAM_USER} -> Confluent Cloud API key."

# --- 3. Secrets ----------------------------------------------------------------
echo ""
echo "[3/7] Creating Gateway secrets..."
_TMPDIR=$(mktemp -d)
trap 'rm -rf "$_TMPDIR"' EXIT

# Confluent Cloud's private endpoints use publicly trusted certificates, so the JVM's
# default cacerts is the right truststore.
JAVA_HOME_DIR=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
cp "${JAVA_HOME_DIR}/lib/security/cacerts" "${_TMPDIR}/truststore.jks"
echo "jksPassword=changeit" > "${_TMPDIR}/jksPassword.txt"
kubectl create secret generic cc-tls \
  --from-file=truststore.jks="${_TMPDIR}/truststore.jks" \
  --from-file=jksPassword.txt="${_TMPDIR}/jksPassword.txt" \
  -n confluent 2>/dev/null || kubectl get secret cc-tls -n confluent >/dev/null

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl create secret generic vault-config \
  --from-literal=address="http://${NODE_IP}:8200" \
  --from-literal=authToken=workshop-token \
  --from-literal=prefixPath=secret/ \
  --from-literal=separator=/ \
  -n confluent 2>/dev/null || kubectl get secret vault-config -n confluent >/dev/null

kubectl create secret generic scram-admin-credentials \
  --from-literal=username="${KAFKA_SCRAM_USER}" \
  --from-literal=password="${KAFKA_SCRAM_PASSWORD}" \
  -n confluent 2>/dev/null || kubectl get secret scram-admin-credentials -n confluent >/dev/null

kubectl create secret generic plain-jaas \
  --from-literal=plain-jaas.conf='org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";' \
  -n confluent 2>/dev/null || kubectl get secret plain-jaas -n confluent >/dev/null
echo "  cc-tls, vault-config (Vault at http://${NODE_IP}:8200), scram-admin-credentials, plain-jaas."

# --- 4. Update the Gateway to the init state ---------------------------------
echo ""
echo "[4/7] Updating the Gateway to init state (adding the Confluent Cloud target)..."
render "${MANIFESTS_DIR}/gateway-init.yaml" | kubectl apply -f -

# --- 5. Wait for the Gateway to stabilize ------------------------------------
echo ""
echo "[5/7] Waiting for the Gateway to stabilize..."
sleep 10
kubectl wait --for=condition=Ready pod -l app=workshop-gateway -n confluent --timeout=300s
echo "  Gateway pods are ready."

# --- 6. Register the SCRAM user through the registration route ---------------
echo ""
echo "[6/7] Registering the SCRAM user with the Gateway..."
cat > "${_TMPDIR}/scram-admin.properties" <<PROPS
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="${KAFKA_SCRAM_USER}" password="${KAFKA_SCRAM_PASSWORD}";
PROPS
kafka-configs.sh --bootstrap-server localhost:9599 \
  --command-config "${_TMPDIR}/scram-admin.properties" \
  --alter \
  --add-config "SCRAM-SHA-512=[iterations=8192,password=${KAFKA_SCRAM_PASSWORD}]" \
  --entity-type users \
  --entity-name "${KAFKA_SCRAM_USER}"
echo "  SCRAM user '${KAFKA_SCRAM_USER}' registered."

# --- 7. Render the switchover CR ---------------------------------------------
echo ""
echo "[7/7] Rendering the switchover CR..."
mkdir -p "${RENDERED_DIR}"
render "${MANIFESTS_DIR}/gateway-switchover.yaml" > "${RENDERED_DIR}/gateway-switchover.yaml"
echo "  ${RENDERED_DIR}/gateway-switchover.yaml"

echo ""
echo "============================================="
echo "  Gateway target configured!"
echo "============================================="
echo ""
echo "  Source cluster:  ${KAFKA_BOOTSTRAP}"
echo "  Target cluster:  ${CC_BOOTSTRAP_SERVERS}"
echo ""
echo "  Continue with STEP-3 (Migrate Data), then 'kcp migration' in STEP-4."
echo "============================================="
