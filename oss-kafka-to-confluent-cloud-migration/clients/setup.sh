#!/bin/bash

# Setup script for the Orders Producer/Consumer (runs on the bastion)

set -e

echo "🚀 Setting up Orders Producer/Consumer for the OSS Kafka -> Confluent Cloud migration"
echo "===================================================================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Install required Python packages into a local virtual environment.
# A venv avoids the "externally-managed-environment" error that Homebrew- and
# Debian-packaged Python raise for a global `pip3 install` (PEP 668), and keeps the
# workshop's dependencies isolated from the system Python.
VENV_DIR="${SCRIPT_DIR}/.venv"
echo "📚 Creating a Python virtual environment (.venv) and installing dependencies..."
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --upgrade pip >/dev/null
"${VENV_DIR}/bin/pip" install -r requirements.txt
echo "  Dependencies installed into ${VENV_DIR}"

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x orders_producer.py orders_consumer.py create_topic.py cutover.sh 2>/dev/null || true

# Create logs directory
echo "📁 Creating logs directory..."
mkdir -p logs

echo ""
echo "✅ Setup complete!"
echo ""
echo "🔧 Next steps:"
echo "  1. Activate the venv (EVERY tab):    source .venv/bin/activate"
echo "  2. Check the source cluster:         source env.oss && python3 kafka_config.py --check"
echo "  3. Deploy the Gateway on k3s:        ../gateway/setup_gateway.sh"
echo "  4. Source the Gateway env:           source env.gateway"
echo "  5. Start the producer:               python3 orders_producer.py"
echo "  6. Start the consumer (new tab):     python3 orders_consumer.py"
echo ""
echo "⚠️  Activate the virtual environment (step 1) in EVERY new terminal tab"
echo "    before running any python3 client, or the 'kafka' module won't be found."
echo ""
echo "🔄 Clients connect through the Gateway for the zero-cut migration."
