#!/bin/bash
# full-deployment.sh - Script completo para desplegar anillo multi-regional

set -e

echo "🌍 Deployment Completo del Anillo Chord DHT Multi-Regional"
echo "==========================================================="

# Verificar argumentos
if [ $# -lt 3 ]; then
    echo "❌ Uso: $0 <VM1_IP> <VM2_IP> <VM3_IP> [BOOTSTRAP_PORT]"
    echo "   Ejemplo: $0 34.73.123.45 35.205.67.89 35.194.12.34 8000"
    echo
    echo "   VM1_IP: IP externa de VM1 (bootstrap)"
    echo "   VM2_IP: IP externa de VM2" 
    echo "   VM3_IP: IP externa de VM3"
    echo "   BOOTSTRAP_PORT: Puerto del bootstrap (default: 8000)"
    exit 1
fi

VM1_IP="$1"
VM2_IP="$2" 
VM3_IP="$3"
BOOTSTRAP_PORT="${4:-8000}"

echo "📝 Configuración del deployment:"
echo "  - VM1 (Bootstrap): $VM1_IP:$BOOTSTRAP_PORT"
echo "  - VM2 (Node 2):    $VM2_IP:$BOOTSTRAP_PORT"
echo "  - VM3 (Node 3):    $VM3_IP:$BOOTSTRAP_PORT"
echo

# Validar formato de IPs
validate_ip() {
    local ip="$1"
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "❌ IP inválida: $ip"
        exit 1
    fi
}

validate_ip "$VM1_IP"
validate_ip "$VM2_IP"
validate_ip "$VM3_IP"

echo "✅ IPs validadas correctamente"

# Generar scripts de deployment para cada VM
echo "📦 Generando scripts de deployment..."

# Script para VM1 (Bootstrap)
cat > "deploy-vm1-bootstrap.sh" << EOF
#!/bin/bash
# Script generado para VM1 (Bootstrap)
echo "🚀 Desplegando Bootstrap Node en VM1..."

cd ~/chord-dht
mkdir -p results

# Detener procesos existentes
pkill -f chord-node || true
sleep 2

# Iniciar bootstrap
nohup ./bin/chord-node \\
    --addr 0.0.0.0:$BOOTSTRAP_PORT \\
    --metrics results/vm1-bootstrap-metrics.csv \\
    --id "vm1-bootstrap-\$(date +%s)" \\
    > vm1-bootstrap.log 2>&1 &

echo "✅ Bootstrap iniciado en VM1"
echo "📋 PID: \$!"
echo "📊 Logs: tail -f vm1-bootstrap.log"
echo "⏳ Esperando 10 segundos para estabilización..."
sleep 10
echo "🎉 Bootstrap listo para recibir conexiones"
EOF

# Script para VM2
cat > "deploy-vm2-node.sh" << EOF
#!/bin/bash
# Script generado para VM2
echo "🚀 Desplegando Node 2 en VM2..."

cd ~/chord-dht
mkdir -p results

# Detener procesos existentes
pkill -f chord-node || true
sleep 2

# Verificar conectividad con bootstrap
echo "🔍 Verificando conectividad con bootstrap $VM1_IP:$BOOTSTRAP_PORT..."
if ! timeout 5 bash -c "echo >/dev/tcp/$VM1_IP/$BOOTSTRAP_PORT"; then
    echo "❌ No se puede conectar al bootstrap: $VM1_IP:$BOOTSTRAP_PORT"
    exit 1
fi

# Iniciar nodo 2
nohup ./bin/chord-node \\
    --addr 0.0.0.0:$BOOTSTRAP_PORT \\
    --bootstrap $VM1_IP:$BOOTSTRAP_PORT \\
    --metrics results/vm2-node2-metrics.csv \\
    --id "vm2-node2-\$(date +%s)" \\
    > vm2-node2.log 2>&1 &

echo "✅ Node 2 iniciado en VM2"
echo "📋 PID: \$!"
echo "📊 Logs: tail -f vm2-node2.log"
echo "⏳ Esperando 15 segundos para estabilización..."
sleep 15
echo "🎉 Node 2 unido al anillo"
EOF

# Script para VM3
cat > "deploy-vm3-node.sh" << EOF
#!/bin/bash  
# Script generado para VM3
echo "🚀 Desplegando Node 3 en VM3..."

cd ~/chord-dht
mkdir -p results

# Detener procesos existentes
pkill -f chord-node || true
sleep 2

# Verificar conectividad con bootstrap
echo "🔍 Verificando conectividad con bootstrap $VM1_IP:$BOOTSTRAP_PORT..."
if ! timeout 5 bash -c "echo >/dev/tcp/$VM1_IP/$BOOTSTRAP_PORT"; then
    echo "❌ No se puede conectar al bootstrap: $VM1_IP:$BOOTSTRAP_PORT"
    exit 1
fi

# Iniciar nodo 3
nohup ./bin/chord-node \\
    --addr 0.0.0.0:$BOOTSTRAP_PORT \\
    --bootstrap $VM1_IP:$BOOTSTRAP_PORT \\
    --metrics results/vm3-node3-metrics.csv \\
    --id "vm3-node3-\$(date +%s)" \\
    > vm3-node3.log 2>&1 &

echo "✅ Node 3 iniciado en VM3"
echo "📋 PID: \$!"
echo "📊 Logs: tail -f vm3-node3.log"
echo "⏳ Esperando 15 segundos para estabilización..."
sleep 15
echo "🎉 Node 3 unido al anillo"
EOF

# Hacer scripts ejecutables
chmod +x deploy-vm1-bootstrap.sh deploy-vm2-node.sh deploy-vm3-node.sh

echo "✅ Scripts generados:"
echo "  - deploy-vm1-bootstrap.sh (para VM1)"
echo "  - deploy-vm2-node.sh (para VM2)"
echo "  - deploy-vm3-node.sh (para VM3)"
echo

# Generar script de verificación del anillo
cat > "verify-ring.sh" << EOF
#!/bin/bash
# Script para verificar el estado del anillo completo

echo "🔍 Verificando Anillo Chord DHT Multi-Regional"
echo "=============================================="

# Verificar cada nodo
echo "📊 Estado de los nodos:"

# VM1 Bootstrap
echo -n "VM1 ($VM1_IP:$BOOTSTRAP_PORT): "
if timeout 3 bash -c "echo >/dev/tcp/$VM1_IP/$BOOTSTRAP_PORT" 2>/dev/null; then
    echo "✅ ACTIVO"
else
    echo "❌ NO RESPONDE"
fi

# VM2 Node 2  
echo -n "VM2 ($VM2_IP:$BOOTSTRAP_PORT): "
if timeout 3 bash -c "echo >/dev/tcp/$VM2_IP/$BOOTSTRAP_PORT" 2>/dev/null; then
    echo "✅ ACTIVO"
else
    echo "❌ NO RESPONDE"
fi

# VM3 Node 3
echo -n "VM3 ($VM3_IP:$BOOTSTRAP_PORT): "
if timeout 3 bash -c "echo >/dev/tcp/$VM3_IP/$BOOTSTRAP_PORT" 2>/dev/null; then
    echo "✅ ACTIVO"
else
    echo "❌ NO RESPONDE"
fi

echo
echo "🧪 Probando lookup distributed:"
if command -v ./bin/chord-simulator >/dev/null 2>&1; then
    ./bin/chord-simulator -nodes 1 -bootstrap $VM1_IP:$BOOTSTRAP_PORT -duration 5s -lookups 10
else
    echo "⚠️  Simulador no disponible para pruebas"
fi
EOF

chmod +x verify-ring.sh

echo "✅ Script de verificación generado: verify-ring.sh"
echo

# Generar instrucciones de deployment
cat > "DEPLOYMENT_INSTRUCTIONS.txt" << EOF
🌍 INSTRUCCIONES DE DEPLOYMENT MULTI-REGIONAL
=============================================

Configuración generada:
- VM1 (Bootstrap): $VM1_IP:$BOOTSTRAP_PORT
- VM2 (Node 2):    $VM2_IP:$BOOTSTRAP_PORT  
- VM3 (Node 3):    $VM3_IP:$BOOTSTRAP_PORT

PASOS PARA EL DEPLOYMENT:

1. 📦 PREPARACIÓN (en todas las VMs):
   - Asegúrate que el proyecto esté clonado en ~/chord-dht
   - Ejecuta: cd ~/chord-dht && make build
   - Verifica: ls -la bin/chord-node

2. 🚀 SECUENCIA DE DEPLOYMENT:

   a) EN VM1 (Bootstrap):
      scp deploy-vm1-bootstrap.sh user@$VM1_IP:~/chord-dht/
      ssh user@$VM1_IP "cd chord-dht && ./deploy-vm1-bootstrap.sh"
      
   b) ESPERAR 30 segundos, luego EN VM2:
      scp deploy-vm2-node.sh user@$VM2_IP:~/chord-dht/
      ssh user@$VM2_IP "cd chord-dht && ./deploy-vm2-node.sh"
      
   c) ESPERAR 30 segundos, luego EN VM3:
      scp deploy-vm3-node.sh user@$VM3_IP:~/chord-dht/
      ssh user@$VM3_IP "cd chord-dht && ./deploy-vm3-node.sh"

3. ✅ VERIFICACIÓN:
   ./verify-ring.sh

4. 📊 MONITOREO:
   En cada VM: cd ~/chord-dht && ./scripts/monitor-ring.sh

COMANDOS ÚTILES:

- Ver logs: tail -f *.log
- Ver métricas: tail -f results/*.csv  
- Estado procesos: ps aux | grep chord-node
- Detener todo: pkill -f chord-node

¡Deployment listo! 🎉
EOF

echo "📋 Instrucciones generadas: DEPLOYMENT_INSTRUCTIONS.txt"
echo
echo "🎯 PRÓXIMOS PASOS:"
echo "1. Copia los scripts a cada VM"
echo "2. Ejecuta los scripts en orden: VM1 → VM2 → VM3"
echo "3. Usa verify-ring.sh para verificar el anillo"
echo "4. Monitorea con scripts/monitor-ring.sh"
echo
echo "📁 Archivos generados:"
ls -la deploy-vm*.sh verify-ring.sh DEPLOYMENT_INSTRUCTIONS.txt 2>/dev/null || true
echo
echo "🎉 ¡Deployment configurado exitosamente!"