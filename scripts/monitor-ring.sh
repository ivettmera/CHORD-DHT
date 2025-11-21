#!/bin/bash
# monitor-ring.sh - Script para monitorear el estado del anillo Chord

set -e

echo "📊 Monitor del Anillo Chord DHT"
echo "================================"

# Configuración
REFRESH_INTERVAL=${REFRESH_INTERVAL:-30}
METRICS_DIR=${METRICS_DIR:-"results"}

# Función para mostrar estado del proceso
check_process() {
    local process_count=$(pgrep -f chord-node | wc -l)
    if [ $process_count -gt 0 ]; then
        echo "✅ Procesos chord-node activos: $process_count"
        echo "   PIDs: $(pgrep -f chord-node | tr '\n' ' ')"
    else
        echo "❌ No hay procesos chord-node ejecutándose"
    fi
}

# Función para mostrar estado de puertos
check_ports() {
    local ports=$(netstat -ln | grep :800 | wc -l)
    if [ $ports -gt 0 ]; then
        echo "✅ Puertos Chord abiertos:"
        netstat -ln | grep :800 | awk '{print "   " $4}' | sort
    else
        echo "❌ No hay puertos Chord abiertos"
    fi
}

# Función para mostrar métricas
show_metrics() {
    echo "📈 Métricas recientes:"
    if ls $METRICS_DIR/*.csv >/dev/null 2>&1; then
        for csv_file in $METRICS_DIR/*.csv; do
            if [ -f "$csv_file" ]; then
                local filename=$(basename "$csv_file")
                local last_line=$(tail -1 "$csv_file" 2>/dev/null | head -1)
                if [ -n "$last_line" ]; then
                    echo "   $filename: $last_line"
                fi
            fi
        done
    else
        echo "   No hay archivos de métricas disponibles"
    fi
}

# Función para mostrar logs recientes
show_recent_logs() {
    echo "📋 Logs recientes:"
    local log_files=$(ls *.log 2>/dev/null | head -3)
    if [ -n "$log_files" ]; then
        for log_file in $log_files; do
            echo "   === $log_file (últimas 2 líneas) ==="
            tail -2 "$log_file" 2>/dev/null | sed 's/^/     /'
        done
    else
        echo "   No hay archivos de log disponibles"
    fi
}

# Función para verificar conectividad entre nodos
check_connectivity() {
    echo "🌐 Verificando conectividad:"
    local bootstrap_port=$(netstat -ln | grep :8000 | head -1)
    if [ -n "$bootstrap_port" ]; then
        echo "   ✅ Nodo local accesible en puerto 8000"
        
        # Intentar conectar a otros nodos si hay información disponible
        if command -v curl >/dev/null 2>&1; then
            if curl -s --connect-timeout 2 http://localhost:8000 >/dev/null 2>&1; then
                echo "   ✅ Servicio HTTP respondiendo"
            else
                echo "   ⚠️  Puerto abierto pero servicio HTTP no responde"
            fi
        fi
    else
        echo "   ❌ No hay nodo local en puerto 8000"
    fi
}

# Función principal de monitoreo
monitor_once() {
    clear
    echo "📊 Monitor del Anillo Chord DHT - $(date)"
    echo "========================================================"
    echo
    
    echo "🔍 Estado de Procesos:"
    check_process
    echo
    
    echo "🌐 Estado de Red:"
    check_ports
    echo
    
    check_connectivity
    echo
    
    show_metrics
    echo
    
    show_recent_logs
    echo
    
    echo "========================================================"
    echo "🔄 Próxima actualización en $REFRESH_INTERVAL segundos..."
    echo "💡 Presiona Ctrl+C para salir"
}

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [opciones]"
    echo
    echo "Opciones:"
    echo "  --once              Ejecutar una sola vez y salir"
    echo "  --interval N        Intervalo de actualización en segundos (default: 30)"
    echo "  --metrics-dir DIR   Directorio de métricas (default: results)"
    echo "  --help              Mostrar esta ayuda"
    echo
    echo "Variables de entorno:"
    echo "  REFRESH_INTERVAL    Intervalo de actualización (segundos)"
    echo "  METRICS_DIR         Directorio de métricas"
}

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --once)
            monitor_once
            exit 0
            ;;
        --interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --metrics-dir)
            METRICS_DIR="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Argumento desconocido: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validar intervalo
if ! [[ "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || [ "$REFRESH_INTERVAL" -lt 1 ]; then
    echo "❌ Intervalo inválido: $REFRESH_INTERVAL"
    exit 1
fi

# Ejecutar monitor continuo
echo "🚀 Iniciando monitor continuo del anillo Chord DHT..."
echo "⏱️  Intervalo de actualización: $REFRESH_INTERVAL segundos"
echo "📁 Directorio de métricas: $METRICS_DIR"
echo

# Configurar señales para salida limpia
trap 'echo -e "\n👋 Monitor detenido"; exit 0' INT TERM

# Loop principal
while true; do
    monitor_once
    sleep "$REFRESH_INTERVAL"
done