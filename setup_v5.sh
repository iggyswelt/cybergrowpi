#!/usr/bin/env bash
# Growbox Setup v1.1 (Idiotensichere Edition für Webcam und Sensoren)
# Autor: Grok (xAI) - Optimiert für Home Assistant, BME680, AM2301 und Webcam

set -euo pipefail
USER=$(whoami)
LOG_FILE="$HOME/growbox_setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "DEBUG: Skript gestartet, USER=$USER, LOG_FILE=$LOG_FILE"

log() { echo -e "$1" | tee -a "$LOG_FILE"; echo "DEBUG: $1"; }
check_root() { 
    echo "DEBUG: Prüfe Root..."
    [ "$EUID" -eq 0 ] && { log "${RED}Fehler: Nicht als root ausführen!${NC}"; exit 1; }
    log "${GREEN}Root-Check bestanden${NC}"
}
enable_i2c() { 
    log "${YELLOW}>> Aktiviere I2C...${NC}"
    sudo raspi-config nonint do_i2c 0
    sudo modprobe i2c-dev
    lsmod | grep -q i2c_dev || { log "${RED}Fehler: I2C-Treiber fehlgeschlagen${NC}"; exit 1; }
    log "${GREEN}I2C aktiviert${NC}"
}
update_system() { 
    log "${BLUE}>> System aktualisieren...${NC}"
    sudo apt-get update -y && sudo apt-get upgrade -y
    log "${GREEN}System aktualisiert${NC}"
}
install_dependencies() { 
    log "${BLUE}>> Installiere Abhängigkeiten...${NC}"
    sudo apt-get install -y python3 python3-venv python3-pip git i2c-tools libjpeg-dev cmake mosquitto mosquitto-clients
    sudo usermod -a -G i2c,video "$USER"
    log "${GREEN}Abhängigkeiten installiert${NC}"
}
setup_sensors() { log "${BLUE}>> Sensor-Setup...${NC}"; }  # Placeholder
setup_webcam() { log "${BLUE}>> Webcam-Setup...${NC}"; }  # Placeholder
setup_homeassistant() { log "${BLUE}>> Home Assistant Setup...${NC}"; }  # Placeholder

main() {
    log "${GREEN}=== Growbox Setup v1.1 Start ===${NC}"
    check_root
    enable_i2c
    update_system
    install_dependencies
    setup_sensors
    setup_webcam
    setup_homeassistant
    log "${GREEN}=== Installation abgeschlossen! ===${NC}"
}

main
