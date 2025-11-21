#!/bin/bash

# Join a new node to the Chord ring  
# Usage: ./join-node.sh [vm_number] [custom_port] [bootstrap_address]
# Examples:
#   ./join-node.sh 2           # VM2 using port 8001
#   ./join-node.sh 3           # VM3 using port 8002  
#   ./join-node.sh 2 8005      # VM2 using custom port 8005

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Source network configuration
if [ -f "config/network.conf" ]; then
    source config/network.conf
else
    echo "Warning: config/network.conf not found, using defaults"
    BOOTSTRAP_ADDR="localhost:8000"
    VM2_PORT=8001
    VM3_PORT=8002
fi

# Parse arguments
VM_NUMBER=${1:-2}  # Default to VM2
CUSTOM_PORT=${2:-}
BOOTSTRAP=${3:-$BOOTSTRAP_ADDR}

# Determine port based on VM number or custom port
if [ -n "$CUSTOM_PORT" ]; then
    NODE_PORT=$CUSTOM_PORT
else
    case $VM_NUMBER in
        1) NODE_PORT=${VM1_PORT:-8000} ;;
        2) NODE_PORT=${VM2_PORT:-8001} ;;
        3) NODE_PORT=${VM3_PORT:-8002} ;;
        *) NODE_PORT=$((8000 + VM_NUMBER - 1)) ;;
    esac
fi

NODE_ADDR="0.0.0.0:$NODE_PORT"
NODE_ID="node-vm${VM_NUMBER}-$(hostname)-$(date +%s)"

echo "=========================================="
echo "CHORD DHT - JOIN NODE"
echo "=========================================="
echo "VM Number: $VM_NUMBER"
echo "Node Address: $NODE_ADDR"
echo "Bootstrap Address: $BOOTSTRAP"
echo "Node ID: $NODE_ID"
echo "=========================================="

# Verify binary exists
if [ ! -f "./bin/chord-node" ]; then
    echo "Error: Binary ./bin/chord-node not found."
    echo "Please run 'make build' first."
    exit 1
fi

# Create directories
mkdir -p results logs

# Build command
CMD="./bin/chord-node --addr $NODE_ADDR --bootstrap $BOOTSTRAP --metrics results/vm${VM_NUMBER}-metrics.csv --id $NODE_ID"

echo "Command: $CMD"
echo "Logs: logs/vm${VM_NUMBER}-join-$(date +%Y%m%d-%H%M%S).log"
echo ""
echo "Starting node... Press Ctrl+C to stop"
echo "=========================================="

# Execute
$CMD 2>&1 | tee "logs/vm${VM_NUMBER}-join-$(date +%Y%m%d-%H%M%S).log"