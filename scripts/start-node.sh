#!/bin/bash

# Script de inicio automático para nodos Chord DHT
# Uso: ./start-node.sh [ADDR] [BOOTSTRAP] [NODE_ID]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Crear directorios necesarios
mkdir -p results logs config

# Cargar configuración si existe
if [ -f "config/network.conf" ]; then
    source config/network.conf
fi

# Parámetros por defecto
ADDR="${1:-0.0.0.0:8000}"
BOOTSTRAP="${2:-}"
NODE_ID="${3:-node-$(hostname)-$(date +%s)}"

# Validar que el binario existe
if [ ! -f "./bin/chord-node" ]; then
    echo "Error: Binary ./bin/chord-node not found. Run 'make build' first."
    exit 1
fi

# Crear comando
CMD="./bin/chord-node --addr $ADDR --metrics results/$(hostname)-metrics.csv --id $NODE_ID"

if [ -n "$BOOTSTRAP" ]; then
    CMD="$CMD --bootstrap $BOOTSTRAP"
    echo "Starting Chord node (joining ring via $BOOTSTRAP)"
else
    echo "Starting Chord node (bootstrap mode)"
fi

echo "Command: $CMD"
echo "Logs will be saved to: logs/$(hostname)-$(date +%Y%m%d-%H%M%S).log"
echo "Press Ctrl+C to stop the node"
echo "=========================================="

# Ejecutar
$CMD 2>&1 | tee "logs/$(hostname)-$(date +%Y%m%d-%H%M%S).log"