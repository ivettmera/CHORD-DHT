#!/bin/bash

# Script de testing para verificar el funcionamiento del anillo Chord DHT
# Realiza múltiples lookups y verifica la respuesta del sistema

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Cargar configuración
source config/network.conf 2>/dev/null || {
    echo "⚠️  Warning: config/network.conf not found"
    echo "   Testing only local nodes"
}

echo "=============================================="
echo "=== Chord DHT Ring Testing ==="
echo "Timestamp: $(date)"
echo "=============================================="
echo

# Función para generar hash SHA-1
generate_hash() {
    echo -n "$1" | sha1sum | cut -d' ' -f1
}

# Lista de nodos a probar
TEST_NODES=("localhost:8000")
if [ -n "$VM2_IP" ]; then TEST_NODES+=("$VM2_IP:8000"); fi
if [ -n "$VM3_IP" ]; then TEST_NODES+=("$VM3_IP:8000"); fi

# Verificar que grpcurl esté disponible
if ! command -v grpcurl >/dev/null 2>&1; then
    echo "❌ grpcurl not found. Install with: sudo apt install grpcurl"
    exit 1
fi

# Verificar que al menos un nodo esté online
online_nodes=()
for node in "${TEST_NODES[@]}"; do
    if timeout 3 grpcurl -plaintext -connect-timeout 2 \
       -d '{"requester":{"id":"test","address":"localhost:8000"}}' \
       "$node" proto.ChordService/Ping >/dev/null 2>&1; then
        online_nodes+=("$node")
    fi
done

if [ ${#online_nodes[@]} -eq 0 ]; then
    echo "❌ No online nodes found. Start the ring first."
    exit 1
fi

echo "✅ Found ${#online_nodes[@]} online nodes: ${online_nodes[*]}"
echo

# Test 1: Ping all nodes
echo "🏓 Test 1: Ping all online nodes"
for node in "${online_nodes[@]}"; do
    echo -n "  Pinging $node: "
    if timeout 5 grpcurl -plaintext -connect-timeout 3 \
       -d '{"requester":{"id":"tester","address":"localhost:8000"}}' \
       "$node" proto.ChordService/Ping >/dev/null 2>&1; then
        echo "✅ Success"
    else
        echo "❌ Failed"
    fi
done
echo

# Test 2: Get node information
echo "📋 Test 2: Get node information"
for node in "${online_nodes[@]}"; do
    echo "  Node $node:"
    node_info=$(timeout 5 grpcurl -plaintext -connect-timeout 3 -d '{}' \
        "$node" proto.ChordService/GetInfo 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$node_info" ]; then
        node_id=$(echo "$node_info" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
        echo "    ID: ${node_id:0:16}..."
        echo "    ✅ GetInfo successful"
    else
        echo "    ❌ GetInfo failed"
    fi
done
echo

# Test 3: FindSuccessor lookups
echo "🔍 Test 3: FindSuccessor lookups (10 random keys)"
test_keys=("user123" "data456" "file789" "key001" "test999" "chord2024" "lookup" "search" "find" "node")

lookup_success=0
lookup_total=0

for key in "${test_keys[@]}"; do
    key_hash=$(generate_hash "$key")
    test_node="${online_nodes[0]}"  # Use first online node
    
    echo -n "  Key '$key' (${key_hash:0:8}...): "
    
    lookup_result=$(timeout 5 grpcurl -plaintext -connect-timeout 3 \
        -d "{\"key\":\"$key_hash\",\"requester\":{\"id\":\"tester\",\"address\":\"localhost:8000\"}}" \
        "$test_node" proto.ChordService/FindSuccessor 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$lookup_result" ]; then
        # Check if successful
        if echo "$lookup_result" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
            successor_id=$(echo "$lookup_result" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
            echo "✅ Found successor: ${successor_id:0:8}..."
            ((lookup_success++))
        else
            echo "❌ Lookup failed"
        fi
    else
        echo "❌ No response"
    fi
    
    ((lookup_total++))
    sleep 0.5
done

echo
echo "📊 Lookup Results: $lookup_success/$lookup_total successful ($(( lookup_success * 100 / lookup_total ))%)"
echo

# Test 4: ClosestPrecedingFinger
echo "👆 Test 4: ClosestPrecedingFinger test"
test_node="${online_nodes[0]}"
test_key=$(generate_hash "testkey123")

echo -n "  Finding closest preceding finger for key ${test_key:0:8}...: "
cpf_result=$(timeout 5 grpcurl -plaintext -connect-timeout 3 \
    -d "{\"key\":\"$test_key\"}" \
    "$test_node" proto.ChordService/ClosestPrecedingFinger 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$cpf_result" ]; then
    if echo "$cpf_result" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
        cpf_id=$(echo "$cpf_result" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
        echo "✅ Found: ${cpf_id:0:8}..."
    else
        echo "❌ Failed"
    fi
else
    echo "❌ No response"
fi
echo

# Test 5: Ring consistency check
echo "🔄 Test 5: Ring consistency check"
declare -A node_successors
declare -A node_predecessors

for node in "${online_nodes[@]}"; do
    node_info=$(timeout 5 grpcurl -plaintext -connect-timeout 3 -d '{}' \
        "$node" proto.ChordService/GetInfo 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$node_info" ]; then
        node_id=$(echo "$node_info" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
        succ_id=$(echo "$node_info" | grep -A5 '"successor"' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
        pred_id=$(echo "$node_info" | grep -A5 '"predecessor"' | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -1)
        
        if [ -n "$node_id" ]; then
            node_successors["$node_id"]="$succ_id"
            node_predecessors["$node_id"]="$pred_id"
            echo "  Node ${node_id:0:8}... -> Successor: ${succ_id:0:8}..., Predecessor: ${pred_id:0:8}..."
        fi
    fi
done

# Verificar consistencia básica
inconsistencies=0
for node_id in "${!node_successors[@]}"; do
    successor="${node_successors[$node_id]}"
    if [ -n "$successor" ] && [ -n "${node_predecessors[$successor]}" ]; then
        if [ "${node_predecessors[$successor]}" != "$node_id" ]; then
            echo "  ⚠️  Inconsistency: Node ${node_id:0:8} points to ${successor:0:8}, but ${successor:0:8} doesn't point back"
            ((inconsistencies++))
        fi
    fi
done

if [ $inconsistencies -eq 0 ]; then
    echo "  ✅ Ring appears consistent"
else
    echo "  ⚠️  Found $inconsistencies potential inconsistencies (may be normal during stabilization)"
fi
echo

# Resumen final
echo "=============================================="
echo "📈 Test Summary:"
echo "  Nodes tested: ${#online_nodes[@]}"
echo "  Lookups successful: $lookup_success/$lookup_total ($(( lookup_success * 100 / lookup_total ))%)"
echo "  Ring consistency: $(( (${#online_nodes[@]} - inconsistencies) * 100 / ${#online_nodes[@]} ))%"

if [ $lookup_success -eq $lookup_total ] && [ $inconsistencies -eq 0 ]; then
    echo "  🎉 Overall status: EXCELLENT"
elif [ $lookup_success -ge $(( lookup_total * 80 / 100 )) ]; then
    echo "  ✅ Overall status: GOOD"
elif [ $lookup_success -ge $(( lookup_total * 50 / 100 )) ]; then
    echo "  ⚠️  Overall status: FAIR (may need stabilization time)"
else
    echo "  ❌ Overall status: POOR (check ring configuration)"
fi

echo "=============================================="