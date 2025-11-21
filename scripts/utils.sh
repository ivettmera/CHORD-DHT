#!/bin/bash
# utils.sh - Utilidades adicionales para manejo del anillo Chord

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar ayuda
show_help() {
    echo "🔧 Utilidades Chord DHT"
    echo "======================"
    echo
    echo "Uso: $0 <comando> [argumentos]"
    echo
    echo "Comandos disponibles:"
    echo "  status                    - Mostrar estado general"
    echo "  stop-all                  - Detener todos los nodos"
    echo "  clean-logs               - Limpiar archivos de log"
    echo "  clean-metrics            - Limpiar archivos de métricas"
    echo "  show-metrics [archivo]   - Mostrar métricas formateadas"
    echo "  test-lookup <bootstrap>  - Probar lookups contra bootstrap"
    echo "  backup-data              - Crear backup de logs y métricas"
    echo "  firewall-setup           - Configurar firewall local"
    echo "  network-test <ip:port>   - Probar conectividad de red"
    echo "  help                     - Mostrar esta ayuda"
}

# Función para mostrar estado
show_status() {
    echo -e "${BLUE}📊 Estado del Sistema Chord DHT${NC}"
    echo "================================="
    echo
    
    # Procesos
    local process_count=$(pgrep -f chord-node 2>/dev/null | wc -l)
    if [ $process_count -gt 0 ]; then
        echo -e "${GREEN}✅ Procesos activos:${NC} $process_count"
        pgrep -f chord-node | while read pid; do
            local cmd=$(ps -p $pid -o args --no-headers 2>/dev/null || echo "Proceso no encontrado")
            echo "   PID $pid: $cmd"
        done
    else
        echo -e "${RED}❌ No hay procesos chord-node ejecutándose${NC}"
    fi
    echo
    
    # Puertos
    local ports=$(netstat -ln 2>/dev/null | grep :800 | wc -l)
    if [ $ports -gt 0 ]; then
        echo -e "${GREEN}✅ Puertos abiertos:${NC}"
        netstat -ln 2>/dev/null | grep :800 | awk '{print "   " $4}' | sort
    else
        echo -e "${RED}❌ No hay puertos Chord abiertos${NC}"
    fi
    echo
    
    # Archivos de datos
    local logs=$(ls *.log 2>/dev/null | wc -l)
    local metrics=$(ls results/*.csv 2>/dev/null | wc -l)
    echo -e "${BLUE}📁 Archivos de datos:${NC}"
    echo "   Logs: $logs archivos"
    echo "   Métricas: $metrics archivos"
    
    if [ $logs -gt 0 ]; then
        echo "   Logs recientes:"
        ls -lt *.log 2>/dev/null | head -3 | awk '{print "     " $9 " (" $5 " bytes)"}'
    fi
}

# Función para detener todos los nodos
stop_all() {
    echo -e "${YELLOW}🛑 Deteniendo todos los nodos Chord...${NC}"
    
    local pids=$(pgrep -f chord-node 2>/dev/null || true)
    if [ -z "$pids" ]; then
        echo -e "${YELLOW}⚠️  No hay procesos chord-node ejecutándose${NC}"
        return 0
    fi
    
    echo "PIDs a detener: $pids"
    
    # Intentar termination graceful
    echo "Enviando SIGTERM..."
    kill $pids 2>/dev/null || true
    sleep 5
    
    # Verificar si siguen corriendo
    local remaining=$(pgrep -f chord-node 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        echo "Enviando SIGKILL a procesos restantes..."
        kill -9 $remaining 2>/dev/null || true
        sleep 2
    fi
    
    # Verificación final
    if pgrep -f chord-node >/dev/null 2>&1; then
        echo -e "${RED}❌ Algunos procesos no pudieron ser detenidos${NC}"
        pgrep -f chord-node | xargs ps -p
    else
        echo -e "${GREEN}✅ Todos los procesos detenidos exitosamente${NC}"
    fi
}

# Función para limpiar logs
clean_logs() {
    echo -e "${YELLOW}🧹 Limpiando archivos de log...${NC}"
    
    local log_count=$(ls *.log 2>/dev/null | wc -l)
    if [ $log_count -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No hay archivos de log para limpiar${NC}"
        return 0
    fi
    
    echo "Archivos de log encontrados: $log_count"
    ls -la *.log 2>/dev/null
    
    echo -n "¿Confirmar eliminación? (y/N): "
    read -r confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -f *.log
        echo -e "${GREEN}✅ Archivos de log eliminados${NC}"
    else
        echo -e "${YELLOW}❌ Operación cancelada${NC}"
    fi
}

# Función para limpiar métricas
clean_metrics() {
    echo -e "${YELLOW}🧹 Limpiando archivos de métricas...${NC}"
    
    if [ ! -d "results" ]; then
        echo -e "${YELLOW}⚠️  Directorio results no existe${NC}"
        return 0
    fi
    
    local metric_count=$(ls results/*.csv 2>/dev/null | wc -l)
    if [ $metric_count -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No hay archivos de métricas para limpiar${NC}"
        return 0
    fi
    
    echo "Archivos de métricas encontrados: $metric_count"
    ls -la results/*.csv 2>/dev/null
    
    echo -n "¿Confirmar eliminación? (y/N): "
    read -r confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -f results/*.csv
        echo -e "${GREEN}✅ Archivos de métricas eliminados${NC}"
    else
        echo -e "${YELLOW}❌ Operación cancelada${NC}"
    fi
}

# Función para mostrar métricas formateadas
show_metrics() {
    local file="$1"
    
    echo -e "${BLUE}📈 Métricas Chord DHT${NC}"
    echo "===================="
    
    if [ -n "$file" ]; then
        if [ ! -f "$file" ]; then
            echo -e "${RED}❌ Archivo no encontrado: $file${NC}"
            return 1
        fi
        files=("$file")
    else
        files=($(ls results/*.csv 2>/dev/null || true))
        if [ ${#files[@]} -eq 0 ]; then
            echo -e "${YELLOW}⚠️  No hay archivos de métricas disponibles${NC}"
            return 0
        fi
    fi
    
    for csv_file in "${files[@]}"; do
        echo -e "\n${BLUE}📊 $(basename "$csv_file"):${NC}"
        
        if [ ! -s "$csv_file" ]; then
            echo -e "${YELLOW}   (archivo vacío)${NC}"
            continue
        fi
        
        # Mostrar header
        echo -e "${YELLOW}   Header:${NC}"
        head -1 "$csv_file" | sed 's/^/     /'
        
        # Mostrar últimas 5 líneas
        echo -e "${YELLOW}   Últimas entradas:${NC}"
        tail -5 "$csv_file" | sed 's/^/     /'
        
        # Estadísticas básicas
        local line_count=$(wc -l < "$csv_file")
        local file_size=$(du -h "$csv_file" | cut -f1)
        echo -e "${YELLOW}   Estadísticas:${NC} $((line_count-1)) entradas, $file_size"
    done
}

# Función para probar lookups
test_lookup() {
    local bootstrap="$1"
    
    if [ -z "$bootstrap" ]; then
        echo -e "${RED}❌ Uso: $0 test-lookup <bootstrap_ip:port>${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🧪 Probando lookups contra: $bootstrap${NC}"
    
    if [ ! -f "bin/chord-simulator" ]; then
        echo -e "${RED}❌ Simulador no encontrado. Ejecuta 'make build' primero.${NC}"
        return 1
    fi
    
    echo "Ejecutando 20 lookups durante 10 segundos..."
    ./bin/chord-simulator -nodes 1 -bootstrap "$bootstrap" -duration 10s -lookups 20
}

# Función para crear backup
backup_data() {
    local backup_dir="backup-$(date +%Y%m%d-%H%M%S)"
    
    echo -e "${BLUE}💾 Creando backup en: $backup_dir${NC}"
    
    mkdir -p "$backup_dir"
    
    # Backup logs
    if ls *.log >/dev/null 2>&1; then
        cp *.log "$backup_dir/"
        echo "✅ Logs respaldados"
    fi
    
    # Backup métricas
    if ls results/*.csv >/dev/null 2>&1; then
        mkdir -p "$backup_dir/results"
        cp results/*.csv "$backup_dir/results/"
        echo "✅ Métricas respaldadas"
    fi
    
    # Crear info del backup
    cat > "$backup_dir/backup-info.txt" << EOF
Backup creado: $(date)
Hostname: $(hostname)
User: $(whoami)
PWD: $(pwd)
Git commit: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
EOF
    
    echo -e "${GREEN}✅ Backup completado: $backup_dir${NC}"
    ls -la "$backup_dir"
}

# Función para configurar firewall
firewall_setup() {
    echo -e "${BLUE}🔥 Configurando firewall para Chord DHT${NC}"
    
    if ! command -v ufw >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  UFW no está instalado${NC}"
        return 1
    fi
    
    echo "Configurando reglas UFW..."
    
    # Permitir SSH
    sudo ufw allow ssh
    
    # Permitir puertos Chord
    sudo ufw allow 8000:8010/tcp comment "Chord DHT"
    
    # Mostrar estado
    sudo ufw status
    
    echo -e "${GREEN}✅ Firewall configurado${NC}"
}

# Función para probar conectividad
network_test() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo -e "${RED}❌ Uso: $0 network-test <ip:port>${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🌐 Probando conectividad a: $target${NC}"
    
    local ip="${target%:*}"
    local port="${target#*:}"
    
    echo "Probando ping a $ip..."
    if ping -c 3 "$ip" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Ping exitoso${NC}"
    else
        echo -e "${RED}❌ Ping falló${NC}"
    fi
    
    echo "Probando conexión TCP a $target..."
    if timeout 5 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
        echo -e "${GREEN}✅ Conexión TCP exitosa${NC}"
    else
        echo -e "${RED}❌ Conexión TCP falló${NC}"
    fi
    
    echo "Probando telnet..."
    if command -v telnet >/dev/null 2>&1; then
        timeout 3 telnet "$ip" "$port" 2>/dev/null || echo -e "${YELLOW}⚠️  Telnet no pudo conectar${NC}"
    else
        echo -e "${YELLOW}⚠️  Telnet no disponible${NC}"
    fi
}

# Procesamiento de comandos
case "${1:-help}" in
    "status")
        show_status
        ;;
    "stop-all")
        stop_all
        ;;
    "clean-logs")
        clean_logs
        ;;
    "clean-metrics")
        clean_metrics
        ;;
    "show-metrics")
        show_metrics "$2"
        ;;
    "test-lookup")
        test_lookup "$2"
        ;;
    "backup-data")
        backup_data
        ;;
    "firewall-setup")
        firewall_setup
        ;;
    "network-test")
        network_test "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac