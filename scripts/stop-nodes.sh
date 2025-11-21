#!/bin/bash

# Script de parada limpia para todos los nodos Chord DHT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=============================================="
echo "=== Stopping Chord DHT Nodes ==="
echo "Timestamp: $(date)"
echo "=============================================="
echo

# Verificar si hay procesos running
chord_processes=$(pgrep -f chord-node)
if [ -z "$chord_processes" ]; then
    echo "✅ No chord-node processes found running"
    exit 0
fi

echo "🔍 Found processes to stop:"
ps aux | grep chord-node | grep -v grep
echo

echo "🛑 Sending SIGTERM for graceful shutdown..."
pkill -SIGTERM chord-node

# Esperar hasta 30 segundos para parada limpia
echo "⏳ Waiting for graceful shutdown (max 30 seconds)..."
for i in {1..30}; do
    if ! pgrep chord-node >/dev/null; then
        echo "✅ All nodes stopped cleanly after $i seconds"
        
        # Verificar que no hay puertos escuchando
        remaining_ports=$(netstat -tln 2>/dev/null | grep ':800[0-9] ')
        if [ -z "$remaining_ports" ]; then
            echo "✅ All network ports released"
        else
            echo "⚠️  Some ports still listening:"
            echo "$remaining_ports"
        fi
        
        exit 0
    fi
    echo -n "."
    sleep 1
done
echo

# Forzar parada si es necesario
echo "⚠️  Graceful shutdown timeout, force stopping remaining nodes..."
pkill -SIGKILL chord-node
sleep 2

# Verificar resultado final
if pgrep chord-node >/dev/null; then
    echo "❌ Warning: Some processes may still be running:"
    ps aux | grep chord-node | grep -v grep
    exit 1
else
    echo "✅ All nodes stopped successfully (forced)"
    
    # Limpiar archivos de lock si existen
    rm -f /tmp/chord-*.lock 2>/dev/null || true
    
    # Mostrar archivos de métricas generados
    if ls results/*.csv >/dev/null 2>&1; then
        echo
        echo "📊 Metrics files preserved:"
        ls -la results/*.csv
    fi
    
    echo "=============================================="
    echo "✅ Shutdown complete"
    echo "=============================================="
fi