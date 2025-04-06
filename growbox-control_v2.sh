#!/usr/bin/env bash
# Growbox Diagnose v1.0 - Überprüft Systemstatus und Dienste
# Autor: Grok (xAI)

LOG_FILE="$HOME/growbox_diagnose.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Dienste zum Überprüfen
SERVICES=("mosquitto" "growsensor.service" "growcam.service" "home-assistant.service")

log() { echo "$TIMESTAMP - $1" | tee -a "$LOG_FILE"; echo -e "$1"; }

check_service() {
    local service=$1
    if systemctl is-active "$service" >/dev/null 2>&1; then
        log "${GREEN}[OK]${NC} $service läuft"
    else
        log "${RED}[FEHLER]${NC} $service ist nicht aktiv"
        read -p "Soll $service gestartet werden? (j/n): " answer
        if [[ "$answer" =~ ^[jJ]$ ]]; then
            log "${YELLOW}>> Starte $service...${NC}"
            sudo systemctl start "$service" && log "${GREEN}>> $service erfolgreich gestartet${NC}" || log "${RED}>> Fehler beim Starten von $service${NC}"
        else
            log "${YELLOW}>> $service wird nicht gestartet${NC}"
        fi
    fi
}

check_hardware() {
    log "${BLUE}=== Hardware-Überprüfung ===${NC}"
    # I2C
    if lsmod | grep -q i2c_dev; then
        log "${GREEN}[OK]${NC} I2C-Treiber geladen"
    else
        log "${RED}[FEHLER]${NC} I2C-Treiber nicht geladen"
    fi
    # Kamera
    if [ -e /dev/video0 ]; then
        log "${GREEN}[OK]${NC} Kamera /dev/video0 erkannt"
    else
        log "${RED}[FEHLER]${NC} Kamera nicht erkannt"
    fi
}

check_system() {
    log "${BLUE}=== System-Überprüfung ===${NC}"
    # Netzwerk
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "${GREEN}[OK]${NC} Netzwerkverbindung vorhanden"
    else
        log "${RED}[FEHLER]${NC} Keine Netzwerkverbindung"
    fi
    # Festplatte
    local usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$usage" -lt 80 ]; then
        log "${GREEN}[OK]${NC} Festplattenauslastung: ${usage}%"
    else
        log "${YELLOW}[WARNUNG]${NC} Festplattenauslastung hoch: ${usage}%"
    fi
    # CPU-Temperatur
    local temp=$(vcgencmd measure_temp | cut -d'=' -f2 | tr -d "'C")
    if [ $(echo "$temp < 70" | bc) -eq 1 ]; then
        log "${GREEN}[OK]${NC} CPU-Temperatur: $temp°C"
    else
        log "${YELLOW}[WARNUNG]${NC} CPU-Temperatur hoch: $temp°C"
    fi
}

main() {
    log "${GREEN}=== Growbox Diagnose Start ===${NC}"
    log "${BLUE}=== Dienste-Überprüfung ===${NC}"
    for service in "${SERVICES[@]}"; do
        check_service "$service"
    done
    check_hardware
    check_system
    ip=$(hostname -I | awk '{print $1}')
    log "${BLUE}=== Zugriffs-Links ===${NC}"
    log "Home Assistant: ${BLUE}http://$ip:8123${NC}"
    log "Webcam-Stream: ${BLUE}http://$ip:8080${NC}"
    log "Diagnose-Log: ${YELLOW}$LOG_FILE${NC}"
    log "${GREEN}=== Diagnose abgeschlossen! ===${NC}"
}

main
