#!/bin/bash

# Configure Gateway with Confluent Cloud target for cutover
# This script:
#   1. Starts Vault (dev mode) for credential mapping
#   2. Stores SCRAM-to-PLAIN credential mappings in Vault
#   3. Creates CC TLS truststore and K8s secrets
#   4. Updates Gateway to full init state (MSK + CC streaming domains)
#   5. Registers SCRAM user via the Gateway registration route
#   6. Renders fenced and switchover CRs to disk for kcp migration
#
# Run this in STEP-2 after target and migration infrastructure are provisioned

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFESTS_DIR="$HOME/clients/gateway-manifests"

# Parse arguments
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <cc-bootstrap-servers> <cc-api-key> <cc-api-secret>"
    echo ""
    echo "  cc-bootstrap-servers  Confluent Cloud cluster bootstrap endpoint"
    echo "  cc-api-key            Cluster API key"
    echo "  cc-api-secret         Cluster API secret"
    echo ""
    echo "These values come from the target_infra terraform output in STEP-2."
    exit 1
fi

export CC_BOOTSTRAP_SERVERS="$1"
export CC_API_KEY="$2"
export CC_API_SECRET="$3"

# Ensure MSK credentials are set
if [ -z "$MSK_BOOTSTRAP_SERVERS" ] || [ -z "$MSK_SASL_USERNAME" ] || [ -z "$MSK_SASL_PASSWORD" ]; then
    echo "MSK environment variables not set. Sourcing env.msk..."
    source "${SCRIPT_DIR}/env.msk"
fi

export MSK_FIRST_BOOTSTRAP=$(echo "$MSK_BOOTSTRAP_SERVERS" | cut -d',' -f1)

echo "============================================="
echo "  Configuring Gateway for Cutover"
echo "============================================="

# Verify Gateway is running
echo ""
echo "[1/8] Verifying Gateway is running..."
if ! kubectl get gateways.platform.confluent.io workshop-gateway -n confluent &>/dev/null; then
    echo "ERROR: Gateway 'workshop-gateway' not found. Run setup_gateway.sh first."
    exit 1
fi
echo "  Gateway is running."

# Start Vault in dev mode
echo ""
echo "[2/8] Starting Vault (dev mode)..."
if ! vault status &>/dev/null 2>&1; then
    nohup vault server -dev \
        -dev-root-token-id="workshop-token" \
        -dev-listen-address="0.0.0.0:8200" \
        > /tmp/vault.log 2>&1 &
    sleep 2
fi
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="workshop-token"
vault status > /dev/null
echo "  Vault is running at ${VAULT_ADDR}"

# Store credential mappings in Vault
echo ""
echo "[3/8] Storing credential mappings in Vault..."
vault kv put secret/${MSK_SASL_USERNAME} value="${CC_API_KEY}/${CC_API_SECRET}"
echo "  Mapped ${MSK_SASL_USERNAME} -> CC API key"

# Create CC TLS truststore and K8s secrets
echo ""
echo "[4/8] Creating secrets..."

# CC TLS truststore (same cacerts as MSK -- both use public CA certs)
JAVA_HOME_DIR=$(dirname $(dirname $(readlink -f $(which java))))
CACERTS="${JAVA_HOME_DIR}/lib/security/cacerts"
_TMPDIR=$(mktemp -d)
trap "rm -rf $_TMPDIR" EXIT
cp "$CACERTS" "${_TMPDIR}/truststore.jks"
echo "jksPassword=changeit" > "${_TMPDIR}/jksPassword.txt"

kubectl create secret generic cc-tls \
    --from-file=truststore.jks="${_TMPDIR}/truststore.jks" \
    --from-file=jksPassword.txt="${_TMPDIR}/jksPassword.txt" \
    -n confluent 2>/dev/null || \
kubectl get secret cc-tls -n confluent > /dev/null
echo "  CC TLS truststore created."

# Vault config secret (Gateway pods need to reach Vault on the host)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl create secret generic vault-config \
    --from-literal=address="http://${NODE_IP}:8200" \
    --from-literal=authToken=workshop-token \
    --from-literal=prefixPath=secret/ \
    --from-literal=separator=/ \
    -n confluent 2>/dev/null || \
kubectl get secret vault-config -n confluent > /dev/null
echo "  Vault config secret created (address: http://${NODE_IP}:8200)."

# SCRAM admin credentials (same user for this workshop)
kubectl create secret generic scram-admin-credentials \
    --from-literal=username="${MSK_SASL_USERNAME}" \
    --from-literal=password="${MSK_SASL_PASSWORD}" \
    -n confluent 2>/dev/null || \
kubectl get secret scram-admin-credentials -n confluent > /dev/null
echo "  SCRAM admin credentials secret created."

# JAAS config template for gateway-to-CC SASL/PLAIN
kubectl create secret generic plain-jaas \
    --from-literal=plain-jaas.conf='org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";' \
    -n confluent 2>/dev/null || \
kubectl get secret plain-jaas -n confluent > /dev/null
echo "  JAAS config template secret created."

# Update Gateway to full init state (adds CC streaming domain + registration route)
echo ""
echo "[5/8] Updating Gateway to init state (adding CC target)..."
envsubst '${MSK_FIRST_BOOTSTRAP} ${CC_BOOTSTRAP_SERVERS}' \
    < "${MANIFESTS_DIR}/gateway-init.yaml" | kubectl apply -f -
echo "  Gateway updated with CC streaming domain."

# Wait for Gateway to stabilize after update
echo ""
echo "[6/8] Waiting for Gateway to stabilize..."
# Pods restart after config change — wait for rollout to complete
sleep 10
# Wait for pods to exist (new pods may not be created yet)
for i in $(seq 1 30); do
    if kubectl get pods -n confluent -l app=workshop-gateway --no-headers 2>/dev/null | grep -q .; then
        break
    fi
    sleep 5
done
kubectl wait --for=condition=Ready pod \
    -l app=workshop-gateway \
    -n confluent \
    --timeout=300s
echo "  Gateway pods are ready."

# Register SCRAM user via the registration route
echo ""
echo "[7/8] Registering SCRAM user with Gateway..."

cat > "${_TMPDIR}/scram-admin.properties" <<PROPS
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="${MSK_SASL_USERNAME}" password="${MSK_SASL_PASSWORD}";
PROPS

kafka-configs --bootstrap-server localhost:9599 \
    --command-config "${_TMPDIR}/scram-admin.properties" \
    --alter \
    --add-config "SCRAM-SHA-512=[iterations=8192,password=${MSK_SASL_PASSWORD}]" \
    --entity-type users \
    --entity-name "${MSK_SASL_USERNAME}"
echo "  SCRAM user '${MSK_SASL_USERNAME}' registered."

# _TMPDIR cleanup handled by trap

# Render fenced and switchover CRs to disk (KCP will apply them during execute)
echo ""
echo "[8/8] Rendering migration CRs..."
RENDERED_DIR="$HOME/gateway-migration-crs"
mkdir -p "$RENDERED_DIR"

envsubst '${MSK_FIRST_BOOTSTRAP} ${CC_BOOTSTRAP_SERVERS}' \
    < "${MANIFESTS_DIR}/gateway-fenced.yaml" > "${RENDERED_DIR}/gateway-fenced.yaml"

envsubst '${CC_BOOTSTRAP_SERVERS}' \
    < "${MANIFESTS_DIR}/gateway-switchover.yaml" > "${RENDERED_DIR}/gateway-switchover.yaml"

echo "  Rendered CRs saved to ${RENDERED_DIR}/"
echo "    - gateway-fenced.yaml"
echo "    - gateway-switchover.yaml"

# Verify configuration
echo ""
echo "  Gateway resources:"
kubectl get gateways.platform.confluent.io -n confluent
echo ""
echo "  Secrets:"
kubectl get secrets -n confluent | grep -E 'msk-tls|cc-tls|vault|scram|plain-jaas'
echo ""

echo "============================================="
echo "  Gateway target configured!"
echo "============================================="
echo ""
echo "  Source cluster:  ${MSK_BOOTSTRAP_SERVERS}"
echo "  Target cluster:  ${CC_BOOTSTRAP_SERVERS}"
echo "  Rendered CRs:    ${RENDERED_DIR}/"
echo ""
echo "  Gateway is ready for zero-cut migration."
echo "  Continue with STEP-3 (Migrate Data), then"
echo "  use 'kcp migration init/execute' in STEP-4."
echo "============================================="
