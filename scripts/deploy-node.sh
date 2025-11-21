#!/bin/bash
# deploy-node.sh - Script para desplegar nodo que se une al anillo

set -e

# Verificar argumentos
if [ $# -lt 1 ]; then
    echo "❌ Uso: $0 <BOOTSTRAP_IP:PORT> [NODE_NAME]"
    echo "   Ejemplo: $0 34.73.123.45:8000 node2"
    exit 1
fi

BOOTSTRAP_ADDR="$1"
NODE_NAME="${2:-node-$(date +%s)}"

echo "🚀 Desplegando Chord DHT Node: $NODE_NAME"

# Configuración
NODE_PORT=${NODE_PORT:-8000}
METRICS_DIR=${METRICS_DIR:-"results"}
NODE_ID="$NODE_NAME-$(date +%s)"

# Crear directorio de métricas
mkdir -p "$METRICS_DIR"

# Función para cleanup en caso de error
cleanup() {
    echo "🧹 Limpiando procesos..."
    pkill -f chord-node || true
}
trap cleanup EXIT

# Verificar que el binario existe
if [ ! -f "bin/chord-node" ]; then
    echo "❌ Binario chord-node no encontrado. Ejecuta 'make build' primero."
    exit 1
fi

# Verificar que el puerto esté disponible
if netstat -ln | grep ":$NODE_PORT " > /dev/null; then
    echo "❌ Puerto $NODE_PORT ya está en uso"
    exit 1
fi

# Verificar conectividad con bootstrap
echo "🔍 Verificando conectividad con bootstrap: $BOOTSTRAP_ADDR"
if ! timeout 5 bash -c "echo >/dev/tcp/${BOOTSTRAP_ADDR/:/ }"; then
    echo "❌ No se puede conectar al bootstrap: $BOOTSTRAP_ADDR"
    echo "💡 Verifica que el bootstrap esté corriendo y sea accesible"
    exit 1
fi

echo "📝 Configuración:"
echo "  - Bootstrap: $BOOTSTRAP_ADDR"
echo "  - Puerto local: $NODE_PORT"
echo "  - Node ID: $NODE_ID"
echo "  - Métricas: $METRICS_DIR"

# Iniciar el nodo
echo "🔄 Iniciando nodo y uniéndose al anillo..."
nohup ./bin/chord-node \
    --addr "0.0.0.0:$NODE_PORT" \
    --bootstrap "$BOOTSTRAP_ADDR" \
    --metrics "$METRICS_DIR/${NODE_NAME}-metrics.csv" \
    --id "$NODE_ID" \
    > "${NODE_NAME}.log" 2>&1 &

NODE_PID=$!
echo "✅ Nodo iniciado con PID: $NODE_PID"

# Esperar a que el nodo esté listo
echo "⏳ Esperando que el nodo se una al anillo..."
for i in {1..60}; do
    if netstat -ln | grep ":$NODE_PORT " > /dev/null; then
        # Verificar en logs que se haya unido al anillo
        if grep -q "joined ring" "${NODE_NAME}.log" 2>/dev/null; then
            echo "✅ Nodo se unió al anillo exitosamente"
            break
        fi
    fi
    if [ $i -eq 60 ]; then
        echo "❌ Timeout esperando que el nodo se una al anillo"
        echo "📋 Últimas líneas del log:"
        tail -10 "${NODE_NAME}.log" 2>/dev/null || echo "No hay logs disponibles"
        exit 1
    fi
    sleep 1
done

# Mostrar información del nodo
echo "📊 Estado del nodo:"
echo "  - Nombre: $NODE_NAME"
echo "  - PID: $NODE_PID"
echo "  - Puerto: $NODE_PORT"
echo "  - Bootstrap: $BOOTSTRAP_ADDR"
echo "  - Logs: ${NODE_NAME}.log"
echo "  - Métricas: $METRICS_DIR/${NODE_NAME}-metrics.csv"

echo "🎉 Nodo $NODE_NAME desplegado exitosamente!"
echo "💡 Para ver logs en tiempo real: tail -f ${NODE_NAME}.log"
echo "💡 Para detener: kill $NODE_PID"

# Mantener el script corriendo si se especifica
if [ "$2" = "--foreground" ] || [ "$3" = "--foreground" ]; then
    echo "🔍 Ejecutando en foreground. Presiona Ctrl+C para salir."
    tail -f "${NODE_NAME}.log"
fi