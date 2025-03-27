#!/bin/bash

# growbox-control.sh - Start-/Überwachungs-Script für die Growbox
# Version 1.0
# Autor: Iggy

# Pfade und Konfiguration
LOG_FILE="/var/log/growbox_control.log"
SERVICES=("growcam.service" "home-assistant@homeassistant" "mosquitto" "grafana-server" "influxdb")

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Funktionen
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        log "${GREEN}[OK]${NC} $service ist aktiv"
        return 0
    else
        log "${RED}[FEHLER]${NC} $service ist inaktiv - starte neu..."
        sudo systemctl restart "$service"
        if [ $? -eq 0 ]; then
            log "${GREEN}[OK]${NC} $service erfolgreich gestartet"
            return 1
        else
            log "${RED}[KRITISCH]${NC} $service konnte nicht gestartet werden"
            return 2
        fi
    fi
}

check_camera() {
    if [ -e "/dev/video0" ]; then
        log "${GREEN}[OK]${NC} Kamera /dev/video0 erkannt"
    else
        log "${RED}[FEHLER]${NC} Kamera /dev/video0 nicht gefunden!"
        return 1
    fi
}

check_disk_space() {
    local threshold=90
    local usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$usage" -ge "$threshold" ]; then
        log "${YELLOW}[WARNUNG]${NC} Festplattenauslastung: $usage% - Aufräumen empfohlen!"
    else
        log "${GREEN}[OK]${NC} Festplattenauslastung: $usage%"
    fi
}

check_network() {
    if ping -c 1 google.com &> /dev/null; then
        log "${GREEN}[OK]${NC} Netzwerkverbindung vorhanden"
    else
        log "${YELLOW}[WARNUNG]${NC} Keine Internetverbindung"
    fi
}

# Hauptroutine
main() {
    log "=== Starte Growbox-Systemprüfung ==="
    
    # Dienste prüfen
    for service in "${SERVICES[@]}"; do
        check_service "$service"
    done
    
    # Hardware prüfen
    check_camera
    check_disk_space
    check_network
    
    # Spezialcheck für mjpg-streamer
    if pgrep mjpg_streamer > /dev/null; then
        log "${GREEN}[OK]${NC} mjpg_streamer Prozess läuft"
    else
        log "${RED}[FEHLER]${NC} mjpg_streamer nicht aktiv - starte Kamera-Service..."
        sudo systemctl restart growcam.service
    fi
    
    # Home Assistant API Check
    if curl -s http://localhost:8123/api/ | grep -q "API running"; then
        log "${GREEN}[OK]${NC} Home Assistant API erreichbar"
    else
        log "${YELLOW}[WARNUNG]${NC} Home Assistant API nicht erreichbar"
    fi
    
    log "=== Prüfung abgeschlossen ==="
}

# Ausführung
main
