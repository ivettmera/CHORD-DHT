#!/bin/bash
# deploy-bootstrap.sh - Script para desplegar nodo bootstrap (VM1)

set -e

echo "🚀 Deployando Chord DHT Bootstrap Node..."

# Configuración
NODE_PORT=${NODE_PORT:-8000}
METRICS_DIR=${METRICS_DIR:-"results"}
NODE_ID=${NODE_ID:-"bootstrap-$(date +%s)"}

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

echo "📝 Configuración:"
echo "  - Puerto: $NODE_PORT"
echo "  - Node ID: $NODE_ID"
echo "  - Métricas: $METRICS_DIR"

# Iniciar el nodo bootstrap
echo "🔄 Iniciando nodo bootstrap..."
nohup ./bin/chord-node \
    --addr "0.0.0.0:$NODE_PORT" \
    --metrics "$METRICS_DIR/bootstrap-metrics.csv" \
    --id "$NODE_ID" \
    > bootstrap.log 2>&1 &

BOOTSTRAP_PID=$!
echo "✅ Bootstrap iniciado con PID: $BOOTSTRAP_PID"

# Esperar a que el nodo esté listo
echo "⏳ Esperando que el nodo esté listo..."
for i in {1..30}; do
    if netstat -ln | grep ":$NODE_PORT " > /dev/null; then
        echo "✅ Nodo bootstrap listo en puerto $NODE_PORT"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Timeout esperando que el nodo esté listo"
        exit 1
    fi
    sleep 1
done

# Mostrar información del nodo
echo "📊 Estado del nodo:"
echo "  - PID: $BOOTSTRAP_PID"
echo "  - Puerto: $NODE_PORT"
echo "  - Logs: bootstrap.log"
echo "  - Métricas: $METRICS_DIR/bootstrap-metrics.csv"

echo "🎉 Bootstrap node desplegado exitosamente!"
echo "💡 Para ver logs en tiempo real: tail -f bootstrap.log"
echo "💡 Para detener: kill $BOOTSTRAP_PID"

# Mantener el script corriendo si se especifica
if [ "$1" = "--foreground" ]; then
    echo "🔍 Ejecutando en foreground. Presiona Ctrl+C para salir."
    tail -f bootstrap.log
fi