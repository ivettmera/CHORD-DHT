#!/bin/bash

# Script de monitoreo para el anillo Chord DHT
# Muestra el estado actual de nodos locales y métricas

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=============================================="
echo "=== Chord DHT Ring Monitor ==="
echo "Timestamp: $(date)"
echo "=============================================="
echo

# Verificar procesos activos
echo "🔍 Active chord-node processes:"
chord_processes=$(ps aux | grep chord-node | grep -v grep)
if [ -n "$chord_processes" ]; then
    echo "$chord_processes"
    echo "✅ Found $(echo "$chord_processes" | wc -l) active processes"
else
    echo "❌ No chord-node processes found"
fi
echo

# Verificar puertos en uso
echo "🌐 Network ports in use:"
ports_info=$(netstat -tlnp 2>/dev/null | grep chord-node || netstat -tln | grep ':800[0-9]')
if [ -n "$ports_info" ]; then
    echo "$ports_info"
else
    echo "❌ No Chord ports (8000-8009) found listening"
fi
echo

# Verificar métricas recientes
echo "📊 Recent metrics (last 5 lines from each file):"
metrics_found=false
for metrics_file in results/*-metrics.csv; do
    if [ -f "$metrics_file" ]; then
        metrics_found=true
        echo "=== $(basename "$metrics_file") ==="
        tail -5 "$metrics_file" 2>/dev/null || echo "Error reading metrics file"
        echo
    fi
done

if [ "$metrics_found" = false ]; then
    echo "❌ No metrics files found in results/"
fi
echo

# Probar conectividad local
echo "🔌 Testing local node connectivity:"
if command -v grpcurl >/dev/null 2>&1; then
    for port in 8000 8001 8002; do
        echo -n "Port $port: "
        if timeout 3 grpcurl -plaintext -d '{}' localhost:$port proto.ChordService/GetInfo >/dev/null 2>&1; then
            echo "✅ Responding"
        else
            echo "❌ Not responding"
        fi
    done
else
    echo "⚠️  grpcurl not installed - install with: sudo apt install grpcurl"
fi
echo

# Mostrar logs recientes si existen
echo "📝 Recent log entries:"
latest_log=$(ls -t logs/*.log 2>/dev/null | head -1)
if [ -n "$latest_log" ] && [ -f "$latest_log" ]; then
    echo "From: $(basename "$latest_log")"
    tail -3 "$latest_log"
else
    echo "❌ No log files found"
fi
echo

echo "=============================================="
echo "=== End Monitor Report ==="
echo "=============================================="