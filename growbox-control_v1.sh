#!/usr/bin/env bash
# Growbox Diagnose-Skript v1.0
# Autor: Iggy & Gemini

# --- Globale Einstellungen ---
LOG_FILE="$HOME/growbox_diagnose.log"

# --- Farbcodierung ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Notfallprotokollierung ---
exec > >(awk '{print strftime("[%Y-%m-%d %H:%M:%S]"), $0}' | tee "$LOG_FILE") 2>&1

# --- Funktionen ---
check_system() {
  echo -e "${BLUE}=== Systemüberprüfung ===${NC}"
  echo -e "${YELLOW}>>> Betriebssystem: $(lsb_release -ds 2>/dev/null || uname -mrs)${NC}"
  echo -e "${YELLOW}>>> Kernel: $(uname -r)${NC}"
  echo -e "${YELLOW}>>> CPU-Temperatur: $(vcgencmd measure_temp 2>/dev/null || echo "Nicht verfügbar")${NC}"
  echo -e "${YELLOW}>>> Arbeitsspeicher: $(free -h | grep Mem)${NC}"
  echo -e "${YELLOW}>>> Festplattenbelegung: $(df -h)${NC}"
  echo -e "${YELLOW}>>> Netzwerk-IP: $(hostname -I)${NC}"
}

check_services() {
  echo -e "${BLUE}=== Dienstüberprüfung ===${NC}"
  check_service "pigpiod"
  check_service "growcam.service"
  check_service "grafana-server"
  check_service "mosquitto"
  check_service "influxdb"
  check_service "mariadb"
  check_service "nginx"
}

check_service() {
  local service_name="$1"
  local status=$(sudo systemctl is-active "$service_name" 2>/dev/null)
  if [ "$status" = "active" ]; then
    echo -e "${GREEN}>>> $service_name: Aktiv${NC}"
  else
    echo -e "${RED}>>> $service_name: Inaktiv${NC}"
    sudo systemctl status "$service_name"
  fi
}

check_hardware() {
  echo -e "${BLUE}=== Hardwareüberprüfung ===${NC}"
  lsmod | grep -q i2c_dev && echo -e "${GREEN}>>> I2C-Treiber: Geladen${NC}" || echo -e "${RED}>>> I2C-Treiber: Nicht geladen${NC}"
  i2cdetect -y 1 && echo -e "${GREEN}>>> I2C-Bus: Erreichbar${NC}" || echo -e "${RED}>>> I2C-Bus: Nicht erreichbar${NC}"
  lsmod | grep -q uvcvideo && echo -e "${GREEN}>>> Kamera-Treiber: Geladen${NC}" || echo -e "${RED}>>> Kamera-Treiber: Nicht geladen${NC}"
  vcgencmd get_camera && echo -e "${GREEN}>>> Kamera: Erkannt${NC}" || echo -e "${RED}>>> Kamera: Nicht erkannt${NC}"
  vcgencmd get_throttled | grep -q "throttled=0x0" && echo -e "${GREEN}>>> Under-voltage: Nicht erkannt${NC}" || echo -e "${YELLOW}>>> Under-voltage: Erkannt${NC}"
}

check_permissions() {
  echo -e "${BLUE}=== Berechtigungsüberprüfung ===${NC}"
  ls -l /dev/video0
  ls -l /dev/i2c-1
}

check_logs() {
  echo -e "${BLUE}=== Logdateien ===${NC}"
  echo -e "${YELLOW}>>> Growbox Setup Log: $HOME/growbox_setup.log${NC}"
  echo -e "${YELLOW}>>> Growbox Diagnose Log: $LOG_FILE${NC}"
  echo -e "${YELLOW}>>> Growcam Service Log: journalctl -u growcam.service${NC}"
  echo -e "${YELLOW}>>> Grafana Service Log: journalctl -u grafana-server${NC}"
}

# --- Hauptprogramm ---
main() {
  echo -e "${BLUE}=== Growbox Diagnose ===${NC}"
  check_system
  check_services
  check_hardware
  check_permissions
  check_logs

  echo -e "${GREEN}\n=== Diagnose abgeschlossen! Details in: $LOG_FILE ===${NC}"
}

main
