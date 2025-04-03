#!/bin/bash

# growbox-control.sh - Start-/Überwachungs-Script für die Growbox
# Version 1.1 (Erweiterte Diagnose)
# Autor: Iggy

# Pfade und Konfiguration
LOG_FILE="/var/log/growbox_control.log"
SERVICES=("growcam.service" "home-assistant@homeassistant" "mosquitto" "grafana-server" "influxdb")
PYTHON_SENSOR_SCRIPT="$HOME/bme680_mqtt.py"
INFLUXDB_HOST="localhost"
INFLUXDB_PORT="8086" # Default InfluxDB port

# Farben
RED='\033${NC} $service ist aktiv"
        return 0
    else
        log "${RED}${NC} $service ist inaktiv - starte neu..."
        sudo systemctl restart "$service"
        if [ $? -eq 0 ]; then
            log "${GREEN}[OK]${NC} $service erfolgreich gestartet"
            return 1
        else
            log "${RED}${NC} $service konnte nicht gestartet werden"
            return 2
        fi
    fi
}

check_camera() {
    if [ -e "/dev/video0" ]; then
        log "${GREEN}[OK]${NC} Kamera /dev/video0 erkannt"
    else
        log "${RED}${NC} Kamera /dev/video0 nicht gefunden!"
        return 1
    fi
}

check_disk_space() {
    local threshold=90
    local usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$usage" -ge "$threshold" ]; then
        log "${YELLOW}${NC} Festplattenauslastung: $usage% - Aufräumen empfohlen!"
    else
        log "${GREEN}[OK]${NC} Festplattenauslastung: $usage%"
    fi
}

check_network() {
    if ping -c 1 google.com &> /dev/null; then
        log "${GREEN}[OK]${NC} Netzwerkverbindung vorhanden"
    else
        log "${YELLOW}${NC} Keine Internetverbindung"
    fi
}

check_python_sensor_script() {
    if; then
        if pgrep -f "$(basename "$PYTHON_SENSOR_SCRIPT")" > /dev/null; then
            log "${GREEN}[OK]${NC} Python Sensor Skript läuft (${PYTHON_SENSOR_SCRIPT})"
        else
            log "${YELLOW}${NC} Python Sensor Skript scheint nicht zu laufen (${PYTHON_SENSOR_SCRIPT})"
        fi
    else
        log "${RED}${NC} Python Sensor Skript nicht gefunden (${PYTHON_SENSOR_SCRIPT})"
    fi
}

check_influxdb() {
    if systemctl is-active --quiet influxdb; then
        log "${GREEN}[OK]${NC} InfluxDB Dienst ist aktiv"
        # Versuche eine einfache Abfrage (erfordert influxdb-cli installiert)
        if command -v influx >/dev/null 2>&1; then
            influx -host "$INFLUXDB_HOST" -port "$INFLUXDB_PORT" -execute 'SHOW DATABASES' &> /dev/null
            if [ $? -eq 0 ]; then
                log "${GREEN}[OK]${NC} InfluxDB reagiert auf Anfragen"
            else
                log "${YELLOW}${NC} InfluxDB scheint nicht auf Anfragen zu reagieren"
            fi
        else
            log "${YELLOW}${NC} InfluxDB CLI (influx) nicht gefunden. Für detailliertere Prüfung installieren."
        fi
    else
        log "${RED}${NC} InfluxDB Dienst ist inaktiv"
    fi
}

# Hauptroutine
main() {
    log "=== Starte Erweiterte Growbox-Systemprüfung ==="
    
    # Dienste prüfen
    for service in "${SERVICES[@]}"; do
        check_service "$service"
    done
    
    # Hardware prüfen
    check_camera
    check_disk_space
    check_network
    
    # Python Sensor Skript prüfen
    check_python_sensor_script
    
    # InfluxDB prüfen
    check_influxdb
    
    # Spezialcheck für mjpg-streamer
    if pgrep mjpg_streamer > /dev/null; then
        log "${GREEN}[OK]${NC} mjpg_streamer Prozess läuft"
    else
        log "${RED}${NC} mjpg_streamer nicht aktiv - starte Kamera-Service..."
        sudo systemctl restart growcam.service
    fi
    
    # Home Assistant API Check
    if curl -s http://localhost:8123/api/ | grep -q "API running"; then
        log "${GREEN}[OK]${NC} Home Assistant API erreichbar"
    else
        log "${YELLOW}${NC} Home Assistant API nicht erreichbar"
    fi
    
    log "=== Erweiterte Prüfung abgeschlossen ==="
}

# Ausführung
main
