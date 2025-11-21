# Guía de Deployment de Chord DHT en 3 VMs de Google Cloud

Esta guía explica cómo desplegar un anillo Chord DHT distribuido en 3 VMs de Google Cloud ubicadas en diferentes regiones.

## Arquitectura del Deployment

```
VM1 (us-central1)    VM2 (europe-west1)    VM3 (asia-east1)
    Bootstrap  ←------- Join ←-------------- Join
    :8000              :8000                :8000
```

## Prerrequisitos

- 3 VMs Linux en Google Cloud (Ubuntu 20.04+ recomendado)
- Go 1.24+ instalado en todas las VMs
- Puertos 8000-8010 abiertos en el firewall
- IPs externas asignadas a todas las VMs

## Paso 1: Configuración de Firewall

En Google Cloud Console, crea las reglas de firewall necesarias:

```bash
# Permitir tráfico gRPC en puertos 8000-8010
gcloud compute firewall-rules create chord-dht-ports \
    --allow tcp:8000-8010 \
    --source-ranges 0.0.0.0/0 \
    --description "Chord DHT communication ports"
```

## Paso 2: Preparación de las VMs

### En todas las VMs (VM1, VM2, VM3):

1. **Clonar el repositorio:**
```bash
cd ~
git clone https://github.com/tu-usuario/chord-dht.git
cd chord-dht

# O si ya tienes el código, sincronízalo
rsync -avz /path/to/local/chord-dht/ vm-user@VM_IP:~/chord-dht/
```

2. **Instalar dependencias:**
```bash
# Instalar protobuf compiler
sudo apt update
sudo apt install -y protobuf-compiler make

# Verificar instalación de Go
go version  # Debe ser 1.24+
```

3. **Compilar el proyecto:**
```bash
cd ~/chord-dht
make build
```

4. **Verificar la compilación:**
```bash
ls -la bin/
# Debe mostrar: chord-node y chord-simulator
```

## Paso 3: Obtener las IPs de las VMs

```bash
# En cada VM, obtener la IP externa
curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip

# O desde tu máquina local
gcloud compute instances list --format="table(name,zone,machineType,status,EXTERNAL_IP)"
```

**Ejemplo de IPs obtenidas:**
- VM1 (us-central1): `34.123.45.67`
- VM2 (europe-west1): `35.234.56.78` 
- VM3 (asia-east1): `36.145.67.89`

## Paso 4: Configuración de Red Interna

### Crear archivo de configuración de red en cada VM:

```bash
# En cada VM, crear ~/chord-dht/config/network.conf
mkdir -p ~/chord-dht/config
cat > ~/chord-dht/config/network.conf << EOF
# Network configuration for Chord DHT
VM1_IP=34.123.45.67
VM2_IP=35.234.56.78
VM3_IP=36.145.67.89
BOOTSTRAP_ADDR=34.123.45.67:8000
EOF
```

## Paso 5: Iniciar el Anillo Chord

### VM1 (Bootstrap Node):

```bash
cd ~/chord-dht

# Crear directorio para métricas
mkdir -p results logs

# Iniciar nodo bootstrap
./bin/chord-node \
    --addr 0.0.0.0:8000 \
    --metrics results/vm1-metrics.csv \
    --id bootstrap-vm1 \
    2>&1 | tee logs/vm1-bootstrap.log
```

**Salida esperada:**
```
2025/11/21 10:00:01 Starting Chord node: ID=7288edd0fc3ffcbe, Address=0.0.0.0:8000
2025/11/21 10:00:01 Node 7288edd0 started on 0.0.0.0:8000
2025/11/21 10:00:01 Creating new ring (bootstrap node)
2025/11/21 10:00:01 Node 7288edd0 created ring
2025/11/21 10:00:01 Node is ready. Press Ctrl+C to stop.
```

### VM2 (Primer Join):

**Esperar 30 segundos** después de que VM1 esté funcionando, luego:

```bash
cd ~/chord-dht

# Crear directorios necesarios
mkdir -p results logs

# Cargar configuración de red
source config/network.conf

# Iniciar nodo y unirse al anillo
./bin/chord-node \
    --addr 0.0.0.0:8000 \
    --bootstrap ${BOOTSTRAP_ADDR} \
    --metrics results/vm2-metrics.csv \
    --id node-vm2-europe \
    2>&1 | tee logs/vm2-join.log
```

**Salida esperada:**
```
2025/11/21 10:00:31 Starting Chord node: ID=a1b2c3d4e5f67890, Address=0.0.0.0:8000
2025/11/21 10:00:31 Node a1b2c3d4 started on 0.0.0.0:8000
2025/11/21 10:00:31 Joining ring via bootstrap: 34.123.45.67:8000
2025/11/21 10:00:32 Node a1b2c3d4 joined ring, successor: 7288edd0
2025/11/21 10:00:32 Node successfully joined ring
```

### VM3 (Segundo Join):

**Esperar 30 segundos** después de que VM2 se haya unido, luego:

```bash
cd ~/chord-dht

# Crear directorios necesarios
mkdir -p results logs

# Cargar configuración de red
source config/network.conf

# Iniciar nodo y unirse al anillo
./bin/chord-node \
    --addr 0.0.0.0:8000 \
    --bootstrap ${BOOTSTRAP_ADDR} \
    --metrics results/vm3-metrics.csv \
    --id node-vm3-asia \
    2>&1 | tee logs/vm3-join.log
```

**Salida esperada:**
```
2025/11/21 10:01:01 Starting Chord node: ID=f9e8d7c6b5a43210, Address=0.0.0.0:8000
2025/11/21 10:01:01 Node f9e8d7c6 started on 0.0.0.0:8000
2025/11/21 10:01:01 Joining ring via bootstrap: 34.123.45.67:8000
2025/11/21 10:01:02 Node f9e8d7c6 joined ring, successor: a1b2c3d4
2025/11/21 10:01:02 Node successfully joined ring
```

## Paso 6: Verificación del Anillo

### Verificar conectividad entre nodos:

En cada VM, ejecutar:

```bash
# Ping a otros nodos para verificar conectividad
cd ~/chord-dht

# Desde VM1, verificar VM2 y VM3
grpcurl -plaintext -d '{"requester":{"id":"test","address":"localhost:8000"}}' \
    35.234.56.78:8000 proto.ChordService/Ping

grpcurl -plaintext -d '{"requester":{"id":"test","address":"localhost:8000"}}' \
    36.145.67.89:8000 proto.ChordService/Ping
```

### Verificar información del anillo:

```bash
# Obtener información de cada nodo
grpcurl -plaintext -d '{}' localhost:8000 proto.ChordService/GetInfo
```

## Paso 7: Monitoreo del Anillo

### Verificar logs en tiempo real:

```bash
# En cada VM
tail -f logs/vm*-*.log
```

### Verificar métricas:

```bash
# Ver métricas CSV generadas
ls -la results/
head -20 results/vm*-metrics.csv
```

**Formato esperado de métricas:**
```
timestamp,nodes,messages,lookups,avg_lookup_ms
2025-11-21T10:00:01Z,1,0,0,0.00
2025-11-21T10:00:06Z,1,5,0,0.00
2025-11-21T10:01:01Z,3,25,0,0.00
```

## Paso 8: Múltiples Nodos por VM (Microservicios)

Para ejecutar múltiples nodos lógicos por VM:

### VM1 (Bootstrap + 2 nodos adicionales):

```bash
cd ~/chord-dht

# Nodo Bootstrap (puerto 8000)
./bin/chord-node --addr 0.0.0.0:8000 --metrics results/vm1-node1.csv --id vm1-node1 &

# Esperar 10 segundos
sleep 10

# Nodos adicionales en VM1
./bin/chord-node --addr 0.0.0.0:8001 --bootstrap localhost:8000 --metrics results/vm1-node2.csv --id vm1-node2 &
./bin/chord-node --addr 0.0.0.0:8002 --bootstrap localhost:8000 --metrics results/vm1-node3.csv --id vm1-node3 &
```

### VM2 (3 nodos):

```bash
cd ~/chord-dht
source config/network.conf

# Nodos en VM2
./bin/chord-node --addr 0.0.0.0:8000 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm2-node1.csv --id vm2-node1 &
sleep 5
./bin/chord-node --addr 0.0.0.0:8001 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm2-node2.csv --id vm2-node2 &
sleep 5
./bin/chord-node --addr 0.0.0.0:8002 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm2-node3.csv --id vm2-node3 &
```

### VM3 (3 nodos):

```bash
cd ~/chord-dht
source config/network.conf

# Nodos en VM3
./bin/chord-node --addr 0.0.0.0:8000 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm3-node1.csv --id vm3-node1 &
sleep 5
./bin/chord-node --addr 0.0.0.0:8001 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm3-node2.csv --id vm3-node2 &
sleep 5
./bin/chord-node --addr 0.0.0.0:8002 --bootstrap ${BOOTSTRAP_ADDR} --metrics results/vm3-node3.csv --id vm3-node3 &
```

## Paso 9: Scripts de Automatización

### Script de inicio automático:

```bash
cat > ~/chord-dht/scripts/start-node.sh << 'EOF'
#!/bin/bash

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

# Crear comando
CMD="./bin/chord-node --addr $ADDR --metrics results/$(hostname)-metrics.csv --id $NODE_ID"

if [ -n "$BOOTSTRAP" ]; then
    CMD="$CMD --bootstrap $BOOTSTRAP"
fi

echo "Starting Chord node with command: $CMD"
echo "Logs will be saved to: logs/$(hostname)-$(date +%Y%m%d-%H%M%S).log"

# Ejecutar
$CMD 2>&1 | tee "logs/$(hostname)-$(date +%Y%m%d-%H%M%S).log"
EOF

chmod +x ~/chord-dht/scripts/start-node.sh
```

### Script de monitoreo:

```bash
cat > ~/chord-dht/scripts/monitor-ring.sh << 'EOF'
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== Chord DHT Ring Monitor ==="
echo "Timestamp: $(date)"
echo

# Verificar procesos activos
echo "Active chord-node processes:"
ps aux | grep chord-node | grep -v grep
echo

# Verificar puertos en uso
echo "Network ports in use:"
netstat -tlnp 2>/dev/null | grep chord-node || netstat -tln | grep ':800[0-9]'
echo

# Verificar métricas recientes
echo "Recent metrics (last 5 lines from each VM):"
for metrics_file in results/*-metrics.csv; do
    if [ -f "$metrics_file" ]; then
        echo "=== $(basename "$metrics_file") ==="
        tail -5 "$metrics_file"
        echo
    fi
done

# Probar conectividad local
echo "Testing local node connectivity:"
if command -v grpcurl >/dev/null 2>&1; then
    grpcurl -plaintext -d '{}' localhost:8000 proto.ChordService/GetInfo 2>/dev/null || echo "Local node not responding"
else
    echo "grpcurl not installed - skipping gRPC tests"
fi
echo

echo "=== End Monitor Report ==="
EOF

chmod +x ~/chord-dht/scripts/monitor-ring.sh
```

## Paso 10: Troubleshooting

### Problema: Nodo no puede conectar al bootstrap

```bash
# Verificar conectividad de red
telnet 34.123.45.67 8000

# Verificar firewall local
sudo ufw status
sudo iptables -L | grep 8000

# Verificar que el bootstrap esté escuchando
netstat -tlnp | grep 8000
```

### Problema: Logs muestran errores de gRPC

```bash
# Verificar versiones de protobuf
protoc --version

# Regenerar archivos protobuf
make proto
make build
```

### Problema: Métricas no se generan

```bash
# Verificar permisos de directorio
ls -la results/
chmod 755 results/

# Verificar espacio en disco
df -h
```

## Comandos de Monitoreo Avanzado

### Ver estado completo del anillo:

```bash
# Script para obtener información de todos los nodos
cat > ~/chord-dht/scripts/ring-status.sh << 'EOF'
#!/bin/bash

source config/network.conf 2>/dev/null || true

echo "=== Chord Ring Status ==="
echo "Timestamp: $(date)"
echo

NODES=("localhost:8000")
if [ -n "$VM2_IP" ]; then NODES+=("$VM2_IP:8000"); fi
if [ -n "$VM3_IP" ]; then NODES+=("$VM3_IP:8000"); fi

for node in "${NODES[@]}"; do
    echo "=== Node: $node ==="
    
    # Ping test
    if grpcurl -plaintext -connect-timeout 5 -d '{"requester":{"id":"monitor","address":"localhost:8000"}}' \
        "$node" proto.ChordService/Ping >/dev/null 2>&1; then
        echo "Status: ONLINE"
        
        # Get node info
        grpcurl -plaintext -connect-timeout 5 -d '{}' \
            "$node" proto.ChordService/GetInfo 2>/dev/null | jq -r '
            "ID: " + .node.id + 
            "\nAddress: " + .node.address + 
            "\nPredecessor: " + (.predecessor.id // "none") + 
            "\nSuccessor: " + (.successor.id // "none") + 
            "\nFingers: " + (.fingers | length | tostring)
            ' 2>/dev/null || echo "Info retrieval failed"
    else
        echo "Status: OFFLINE or UNREACHABLE"
    fi
    echo
done
EOF

chmod +x ~/chord-dht/scripts/ring-status.sh
```

## Detener el Anillo

### Detener ordenadamente todos los nodos:

```bash
# Script de parada limpia
cat > ~/chord-dht/scripts/stop-nodes.sh << 'EOF'
#!/bin/bash

echo "Stopping all Chord nodes..."

# Enviar SIGTERM para parada limpia
pkill -SIGTERM chord-node

# Esperar hasta 30 segundos para parada limpia
for i in {1..30}; do
    if ! pgrep chord-node >/dev/null; then
        echo "All nodes stopped cleanly"
        exit 0
    fi
    sleep 1
done

# Forzar parada si es necesario
echo "Force stopping remaining nodes..."
pkill -SIGKILL chord-node

# Verificar que no queden procesos
if pgrep chord-node >/dev/null; then
    echo "Warning: Some processes may still be running"
    ps aux | grep chord-node
else
    echo "All nodes stopped successfully"
fi
EOF

chmod +x ~/chord-dht/scripts/stop-nodes.sh
```

## Resumen de Comandos Rápidos

```bash
# Preparación inicial en todas las VMs
cd ~ && git clone <repo> && cd chord-dht && make build

# VM1 - Bootstrap
./scripts/start-node.sh 0.0.0.0:8000

# VM2/VM3 - Join (reemplazar BOOTSTRAP_IP)
./scripts/start-node.sh 0.0.0.0:8000 BOOTSTRAP_IP:8000

# Monitoreo
./scripts/monitor-ring.sh
./scripts/ring-status.sh

# Detener
./scripts/stop-nodes.sh
```

¡El anillo Chord DHT distribuido en 3 regiones de Google Cloud está listo y funcionando con herramientas de monitoreo y administración completas!