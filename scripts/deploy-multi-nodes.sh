#!/bin/bash

# Script de despliegue automático para múltiples nodos por VM
# Uso: ./deploy-multi-nodes.sh [VM_ROLE] [NODE_COUNT]
# VM_ROLE: bootstrap, join
# NODE_COUNT: número de nodos a ejecutar en esta VM (default: 3)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Parámetros
VM_ROLE="${1:-join}"
NODE_COUNT="${2:-3}"
BASE_PORT=8000

# Cargar configuración
if [ -f "config/network.conf" ]; then
    source config/network.conf
    echo "✅ Loaded network configuration"
else
    echo "⚠️  No network.conf found, using defaults"
    BOOTSTRAP_ADDR="localhost:8000"
fi

echo "=============================================="
echo "=== Chord DHT Multi-Node Deployment ==="
echo "VM Role: $VM_ROLE"
echo "Node Count: $NODE_COUNT"
echo "Base Port: $BASE_PORT"
echo "Bootstrap: $BOOTSTRAP_ADDR"
echo "Timestamp: $(date)"
echo "=============================================="
echo

# Crear directorios necesarios
mkdir -p results logs config pids

# Verificar que el binario existe
if [ ! -f "./bin/chord-node" ]; then
    echo "❌ Binary ./bin/chord-node not found. Running make build..."
    make build
    if [ ! -f "./bin/chord-node" ]; then
        echo "❌ Build failed. Exiting."
        exit 1
    fi
fi

# Función para iniciar un nodo
start_node() {
    local port=$1
    local node_id=$2
    local bootstrap_addr=$3
    local is_bootstrap=$4
    
    local cmd="./bin/chord-node --addr 0.0.0.0:$port --metrics results/$(hostname)-node$node_id-metrics.csv --id $(hostname)-node$node_id"
    
    if [ "$is_bootstrap" != "true" ]; then
        cmd="$cmd --bootstrap $bootstrap_addr"
    fi
    
    echo "🚀 Starting node $node_id on port $port..."
    echo "   Command: $cmd"
    
    # Iniciar el nodo en background y guardar PID
    nohup $cmd > "logs/$(hostname)-node$node_id-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
    local pid=$!
    echo $pid > "pids/node$node_id.pid"
    
    echo "   ✅ Started with PID: $pid"
    
    # Verificar que el proceso inició correctamente
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        echo "   ✅ Node $node_id is running"
        
        # Verificar que el puerto esté escuchando
        local attempts=0
        while [ $attempts -lt 10 ]; do
            if netstat -tln 2>/dev/null | grep -q ":$port "; then
                echo "   ✅ Port $port is listening"
                return 0
            fi
            sleep 1
            ((attempts++))
        done
        echo "   ⚠️  Port $port not listening yet (may be starting up)"
    else
        echo "   ❌ Node $node_id failed to start"
        return 1
    fi
}

# Detener nodos existentes si hay alguno
if ls pids/*.pid >/dev/null 2>&1; then
    echo "🛑 Stopping existing nodes..."
    for pid_file in pids/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid"
                echo "   Stopped PID: $pid"
            fi
            rm -f "$pid_file"
        fi
    done
    sleep 3
fi

# Verificar puertos disponibles
echo "🔍 Checking port availability..."
for ((i=0; i<NODE_COUNT; i++)); do
    port=$((BASE_PORT + i))
    if netstat -tln 2>/dev/null | grep -q ":$port "; then
        echo "❌ Port $port is already in use"
        echo "   Please stop existing services or change BASE_PORT"
        exit 1
    fi
done
echo "✅ All ports available"
echo

# Despliegue según el rol de la VM
if [ "$VM_ROLE" = "bootstrap" ]; then
    echo "🌟 Deploying as BOOTSTRAP VM"
    
    # Primer nodo es bootstrap
    start_node $BASE_PORT 1 "" true
    
    # Esperar un poco más para que el bootstrap se establezca
    echo "⏳ Waiting for bootstrap to stabilize..."
    sleep 10
    
    # Resto de nodos se unen al bootstrap local
    for ((i=1; i<NODE_COUNT; i++)); do
        port=$((BASE_PORT + i))
        node_id=$((i + 1))
        
        echo "⏳ Waiting 5 seconds before starting next node..."
        sleep 5
        
        start_node $port $node_id "localhost:$BASE_PORT" false
    done
    
else
    echo "🔗 Deploying as JOIN VM"
    
    # Verificar que el bootstrap es accesible
    if [ -n "$BOOTSTRAP_ADDR" ]; then
        bootstrap_host=$(echo $BOOTSTRAP_ADDR | cut -d':' -f1)
        bootstrap_port=$(echo $BOOTSTRAP_ADDR | cut -d':' -f2)
        
        echo "🔍 Testing bootstrap connectivity: $BOOTSTRAP_ADDR"
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$bootstrap_host/$bootstrap_port"; then
            echo "✅ Bootstrap is reachable"
        else
            echo "❌ Bootstrap $BOOTSTRAP_ADDR is not reachable"
            echo "   Make sure the bootstrap VM is running and network is configured"
            exit 1
        fi
    fi
    
    # Todos los nodos se unen al bootstrap remoto
    for ((i=0; i<NODE_COUNT; i++)); do
        port=$((BASE_PORT + i))
        node_id=$((i + 1))
        
        if [ $i -gt 0 ]; then
            echo "⏳ Waiting 5 seconds before starting next node..."
            sleep 5
        fi
        
        start_node $port $node_id "$BOOTSTRAP_ADDR" false
    done
fi

echo
echo "=============================================="
echo "✅ Deployment completed!"
echo

# Mostrar resumen
echo "📊 Deployment Summary:"
echo "   VM Role: $VM_ROLE"
echo "   Nodes started: $NODE_COUNT"
echo "   Ports used: $BASE_PORT-$((BASE_PORT + NODE_COUNT - 1))"
echo "   PIDs saved in: pids/"
echo "   Logs saved in: logs/"
echo "   Metrics in: results/"
echo

# Mostrar procesos activos
echo "🔍 Active processes:"
ps aux | grep chord-node | grep -v grep

echo
echo "=============================================="
echo "🎯 Next steps:"
echo "   1. Monitor with: ./scripts/monitor.sh"
echo "   2. Check ring status: ./scripts/ring-status.sh"
echo "   3. Test functionality: ./scripts/test-ring.sh"
echo "   4. Stop all nodes: ./scripts/stop-nodes.sh"
echo "=============================================="