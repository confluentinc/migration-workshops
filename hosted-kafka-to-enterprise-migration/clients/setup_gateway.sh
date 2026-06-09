#!/bin/bash

# Setup script for Confluent Gateway on k3s
# Deploys a passthrough Gateway routing SCRAM traffic to MSK
# Run this after setup.sh during STEP-0

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFESTS_DIR="$HOME/clients/gateway-manifests"

echo "============================================="
echo "  Deploying Confluent Gateway"
echo "============================================="

# Verify k3s is running
echo ""
echo "[1/7] Verifying Kubernetes (k3s) is running..."
if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: k3s is not running. Ensure the bastion host was provisioned correctly."
    exit 1
fi
# Check for DiskPressure (causes pod evictions and scheduling failures)
if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="DiskPressure")].status}' 2>/dev/null | grep -q "True"; then
    echo "ERROR: Node has DiskPressure. Free disk space before continuing:"
    echo "  rm -f /home/ec2-user/confluent-8.0.0.tar.gz"
    echo "  sudo k3s crictl rmi --prune"
    echo "  kubectl delete pods --all-namespaces --field-selector=status.phase==Failed"
    echo "  Then wait ~1 minute for the node to clear the condition."
    exit 1
fi
echo "  Kubernetes is ready."

# Verify environment variables
echo ""
echo "[2/7] Verifying MSK environment variables..."
if [ -z "$MSK_BOOTSTRAP_SERVERS" ]; then
    echo "ERROR: MSK_BOOTSTRAP_SERVERS is not set. Run 'source env.msk' first."
    exit 1
fi
if [ -z "$MSK_SASL_USERNAME" ] || [ -z "$MSK_SASL_PASSWORD" ]; then
    echo "ERROR: MSK_SASL_USERNAME and MSK_SASL_PASSWORD must be set."
    exit 1
fi
echo "  MSK bootstrap: ${MSK_BOOTSTRAP_SERVERS}"
echo "  MSK username:  ${MSK_SASL_USERNAME}"

# Extract first bootstrap server for Gateway endpoint
export MSK_FIRST_BOOTSTRAP=$(echo "$MSK_BOOTSTRAP_SERVERS" | cut -d',' -f1)
echo "  Gateway will connect to: ${MSK_FIRST_BOOTSTRAP}"

# Install CFK operator via Helm
echo ""
echo "[3/7] Installing Confluent for Kubernetes (CFK) operator..."
helm repo add confluentinc https://packages.confluent.io/helm 2>/dev/null || true
helm repo update
kubectl create namespace confluent 2>/dev/null || true

# Recover from a stuck Helm release (e.g., previous run crashed mid-install)
RELEASE_STATUS=$(helm status confluent-operator -n confluent -o json 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)
if [[ "$RELEASE_STATUS" == pending-* ]]; then
    echo "  Detected stuck release (status: ${RELEASE_STATUS}). Rolling back..."
    helm rollback confluent-operator 0 -n confluent || helm uninstall confluent-operator -n confluent
fi

helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes \
    --namespace confluent \
    --set namespaced=false \
    --wait --timeout 5m
echo "  CFK operator installed."

# Create MSK TLS truststore secret
echo ""
echo "[4/7] Creating MSK TLS truststore..."
JAVA_HOME_DIR=$(dirname $(dirname $(readlink -f $(which java))))
CACERTS="${JAVA_HOME_DIR}/lib/security/cacerts"

if [ ! -f "$CACERTS" ]; then
    echo "ERROR: Java cacerts not found at ${CACERTS}"
    exit 1
fi

_TMPDIR=$(mktemp -d)
trap "rm -rf $_TMPDIR" EXIT
cp "$CACERTS" "${_TMPDIR}/truststore.jks"
echo "jksPassword=changeit" > "${_TMPDIR}/jksPassword.txt"

kubectl create secret generic msk-tls \
    --from-file=truststore.jks="${_TMPDIR}/truststore.jks" \
    --from-file=jksPassword.txt="${_TMPDIR}/jksPassword.txt" \
    -n confluent 2>/dev/null || \
kubectl get secret msk-tls -n confluent > /dev/null
echo "  MSK TLS truststore created."

# Deploy passthrough Gateway
echo ""
echo "[5/7] Deploying Gateway (passthrough to MSK)..."
envsubst '${MSK_FIRST_BOOTSTRAP}' < "${MANIFESTS_DIR}/gateway-passthrough.yaml" | kubectl apply -f -
echo "  Gateway manifests applied."

# Wait for Gateway to be ready
echo ""
echo "[6/7] Waiting for Gateway to be ready..."

# Wait for the Gateway CRD resource to exist
echo "  Waiting for Gateway resource to be registered..."
for i in $(seq 1 30); do
    if kubectl get gateways.platform.confluent.io workshop-gateway -n confluent &>/dev/null; then
        echo "  Gateway resource found."
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Timed out waiting for Gateway resource. Check CFK operator logs:"
        echo "  kubectl logs -n confluent -l app=confluent-operator"
        exit 1
    fi
    sleep 10
done

# Wait for Gateway pods to exist
echo "  Waiting for Gateway pods..."
for i in $(seq 1 30); do
    if kubectl get pods -n confluent -l app=workshop-gateway --no-headers 2>/dev/null | grep -q .; then
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Timed out waiting for Gateway pods to be created."
        exit 1
    fi
    sleep 10
done

# Wait for Gateway pods to be ready
kubectl wait --for=condition=Ready pod \
    -l app=workshop-gateway \
    -n confluent \
    --timeout=300s

# Verify Gateway is accessible
echo ""
echo "[7/7] Verifying Gateway deployment..."
echo ""
echo "  Gateway resources:"
kubectl get gateways.platform.confluent.io -n confluent 2>/dev/null || \
    echo "  (CRD status check - Gateway may still be initializing)"
echo ""
echo "  Gateway pods:"
kubectl get pods -n confluent -l app=workshop-gateway 2>/dev/null || \
    kubectl get pods -n confluent
echo ""

echo "============================================="
echo "  Gateway deployed successfully!"
echo "============================================="
echo ""
echo "  Gateway endpoint: localhost:9595"
echo ""
echo "  Next steps:"
echo "  1. Source env.gateway:  source env.gateway"
echo "  2. Test producer:       python3 orders_producer.py"
echo "  3. Test consumer:       python3 orders_consumer.py"
echo ""
echo "  Clients connect through Gateway using SCRAM,"
echo "  which transparently routes traffic to MSK."
echo "============================================="
