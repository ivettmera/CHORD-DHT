#!/bin/bash

# Script de estado completo del anillo Chord DHT
# Obtiene información de todos los nodos remotos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Cargar configuración de red si existe
source config/network.conf 2>/dev/null || {
    echo "⚠️  Warning: config/network.conf not found"
    echo "   Create it with VM IPs for full ring status"
    echo
}

echo "=============================================="
echo "=== Chord Ring Status ==="
echo "Timestamp: $(date)"
echo "=============================================="
echo

# Lista de nodos a verificar
NODES=("localhost:8000")
if [ -n "$VM2_IP" ]; then NODES+=("$VM2_IP:8000"); fi
if [ -n "$VM3_IP" ]; then NODES+=("$VM3_IP:8000"); fi

# Agregar puertos adicionales locales
NODES+=("localhost:8001" "localhost:8002")

echo "🔍 Checking ${#NODES[@]} potential nodes..."
echo

for node in "${NODES[@]}"; do
    echo "=== Node: $node ==="
    
    # Verificar si grpcurl está disponible
    if ! command -v grpcurl >/dev/null 2>&1; then
        echo "❌ grpcurl not available - install with: sudo apt install grpcurl"
        continue
    fi
    
    # Ping test
    if timeout 5 grpcurl -plaintext -connect-timeout 3 \
        -d '{"requester":{"id":"monitor","address":"localhost:8000"}}' \
        "$node" proto.ChordService/Ping >/dev/null 2>&1; then
        
        echo "✅ Status: ONLINE"
        
        # Get node info
        node_info=$(timeout 5 grpcurl -plaintext -connect-timeout 3 -d '{}' \
            "$node" proto.ChordService/GetInfo 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$node_info" ]; then
            # Parsear la información (sin jq para máxima compatibilidad)
            node_id=$(echo "$node_info" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
            node_addr=$(echo "$node_info" | grep -o '"address"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
            
            # Buscar predecessor y successor
            pred_id=$(echo "$node_info" | grep -A5 '"predecessor"' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
            succ_id=$(echo "$node_info" | grep -A5 '"successor"' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
            
            # Contar fingers
            finger_count=$(echo "$node_info" | grep -o '"fingers"' | wc -l)
            
            echo "   🆔 ID: ${node_id:-unknown}"
            echo "   📍 Address: ${node_addr:-unknown}"
            echo "   ⬅️  Predecessor: ${pred_id:-none}"
            echo "   ➡️  Successor: ${succ_id:-none}"
            echo "   👆 Fingers: ${finger_count:-0}"
        else
            echo "   ⚠️  Node responded to ping but GetInfo failed"
        fi
    else
        echo "❌ Status: OFFLINE or UNREACHABLE"
        
        # Verificar si es un nodo local
        if [[ "$node" == localhost:* ]]; then
            port=$(echo "$node" | cut -d':' -f2)
            if netstat -tln 2>/dev/null | grep -q ":$port "; then
                echo "   ℹ️  Port $port is listening but gRPC not responding"
            else
                echo "   ℹ️  Port $port is not listening"
            fi
        fi
    fi
    echo
done

# Resumen del anillo
echo "=============================================="
echo "📈 Ring Summary:"

online_count=0
for node in "${NODES[@]}"; do
    if command -v grpcurl >/dev/null 2>&1 && \
       timeout 3 grpcurl -plaintext -connect-timeout 2 \
       -d '{"requester":{"id":"monitor","address":"localhost:8000"}}' \
       "$node" proto.ChordService/Ping >/dev/null 2>&1; then
        ((online_count++))
    fi
done

echo "   Online nodes: $online_count / ${#NODES[@]}"
echo "   Ring health: $(( online_count * 100 / ${#NODES[@]} ))%"

if [ $online_count -ge 3 ]; then
    echo "   ✅ Ring appears healthy"
elif [ $online_count -ge 1 ]; then
    echo "   ⚠️  Ring partially functional"
else
    echo "   ❌ Ring appears down"
fi

echo "=============================================="