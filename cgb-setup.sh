#!/bin/bash
# Ultimate Growbox Setup v5.1 ("Stable Pigpio Edition")
# Autor: Iggy & DeepSeek
# Features:
# - Stabiles Pigpio-Setup
# - Verbesserte Fehlerbehandlung
# - Hardware-unabhängige Installation
# - Automatische Selbstdiagnose

# --- Konfiguration ---
USER="Iggy"
LOG_FILE="$HOME/growbox_setup.log"
VENV_DIR="$HOME/growbox_venv"
HA_DIR="/srv/homeassistant"

# Farbcodierung
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Initialisierung ---
init() {
  echo -e "${BLUE}=== Initialisiere Growbox Setup v5.1 ===${NC}"
  exec > >(tee "$LOG_FILE") 2>&1
  trap "cleanup" EXIT
  check_root
  kill_conflicting_processes
}

cleanup() {
  echo -e "${BLUE}=== Aufräumen... ===${NC}"
  sudo systemctl restart pigpiod 2>/dev/null
  exit 0
}

check_root() {
  if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Fehler: Nicht als root ausführen!${NC}"
    exit 1
  fi
}

kill_conflicting_processes() {
  echo -e "${YELLOW}>>> Beende konkurrierende Prozesse...${NC}"
  sudo pkill pigpiod || true
  sudo pkill mjpg_streamer || true
  sudo rm -f /var/run/pigpio.pid
}

# --- Systemvorbereitung ---
prepare_system() {
  echo -e "${BLUE}>>> Systemaktualisierung...${NC}"
  sudo apt update && sudo apt full-upgrade -y
  sudo apt install -y git python3 python3-venv python3-pip \
    i2c-tools libgpiod2 libjpeg62-turbo-dev libv4l-dev \
    mosquitto influxdb grafana-enterprise mariadb-server pigpio || {
    echo -e "${RED}>>> Kritischer Fehler bei Paketinstallation!${NC}"
    exit 1
  }
}

# --- Sensoren & Pigpio ---
setup_sensors() {
  echo -e "${BLUE}>>> Sensor-Setup...${NC}"
  python3 -m venv "$VENV_DIR" || return 1
  source "$VENV_DIR/bin/activate"
  
  pip install --upgrade pip wheel || critical_error "Pip-Update fehlgeschlagen"
  pip install adafruit-circuitpython-dht RPi.GPIO || 
    pip install pigpio-dht ||
    pip install Adafruit_DHT || 
    critical_error "Sensor-Bibliotheken können nicht installiert werden"

  setup_pigpio_service
  setup_gpio_config
  deactivate
}

setup_pigpio_service() {
  echo -e "${YELLOW}>>> Konfiguriere Pigpio-Daemon...${NC}"
  
  # Alte PID entfernen
  sudo rm -f /var/run/pigpio.pid
  
  # Neue Service-Datei
  sudo tee /etc/systemd/system/pigpiod.service > /dev/null <<EOF
[Unit]
Description=GPIO Daemon
After=network.target
StartLimitIntervalSec=0

[Service]
Type=forking
ExecStart=/usr/bin/pigpiod -l -t 0
ExecStop=/bin/rm -f /var/run/pigpio.pid
Restart=always
RestartSec=5
User=root
PIDFile=/var/run/pigpio.pid

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable pigpiod
  sudo systemctl restart pigpiod
  
  # Warte und prüfe Status
  sleep 5
  if ! systemctl is-active --quiet pigpiod; then
    echo -e "${YELLOW}>>> Debug: Manueller Startversuch...${NC}"
    sudo pigpiod -l -t 0
    sleep 3
    if pgrep pigpiod; then
      echo -e "${GREEN}✔ Pigpio läuft manuell${NC}"
    else
      echo -e "${RED}✘ Pigpio startet nicht. Details:${NC}"
      journalctl -u pigpiod -b --no-pager | tail -20
      critical_error "Pigpio konnte nicht gestartet werden"
    fi
  fi
}

setup_gpio_config() {
  echo -e "${YELLOW}>>> Aktiviere Hardware-Schnittstellen...${NC}"
  sudo raspi-config nonint do_i2c 0
  sudo raspi-config nonint do_serial 0
  sudo sed -i '/dtparam=i2c_arm/d' /boot/config.txt
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
}

# --- Kamera-Setup ---
setup_camera() {
  echo -e "${BLUE}>>> Kamera-Installation...${NC}"
  [ -d "$HOME/mjpg-streamer" ] || {
    git clone https://github.com/jacksonliam/mjpg-streamer.git "$HOME/mjpg-streamer"
    cd "$HOME/mjpg-streamer/mjpg-streamer-experimental" || return
    make && sudo make install
  }

  sudo tee /etc/systemd/system/growcam.service > /dev/null <<EOF
[Unit]
Description=Growbox Camera Service
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d /dev/video0" -o "output_http.so -p 8080"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable --now growcam.service || {
    echo -e "${YELLOW}>>> Kamera-Fallback: Manueller Start...${NC}"
    mjpg_streamer -i "input_uvc.so" -o "output_http.so" &
  }
}

# --- Diagnose-System ---
final_check() {
  echo -e "${BLUE}=== Finaler Systemcheck ===${NC}"
  check_service "pigpiod"
  check_service "growcam.service"
  check_port 8080 "Kamera-Stream"
  check_sensor_values
  
  # Erstelle Diagnose-Tool
  create_diag_tool
}

check_service() {
  if systemctl is-active --quiet "$1"; then
    echo -e "${GREEN}✔ $1 läuft${NC}"
  else
    echo -e "${RED}✘ $1 nicht aktiv${NC}"
  fi
}

check_port() {
  if ss -tuln | grep -q ":$1 "; then
    echo -e "${GREEN}✔ Port $1 ($2) offen${NC}"
  else
    echo -e "${RED}✘ Port $1 ($2) blockiert${NC}"
  fi
}

check_sensor_values() {
  echo -e "${YELLOW}>>> Sensortest...${NC}"
  source "$VENV_DIR/bin/activate"
  python3 -c "import pigpio; print('Pigpio:', 'OK' if pigpio.pi().connected else 'FEHLER')" || true
  python3 -c "import board; print('I2C-Bus:', 'OK' if board.I2C().try_lock() else 'FEHLER')" || true
  deactivate
}

create_diag_tool() {
  sudo tee /usr/local/bin/growbox-diag > /dev/null <<'EOF'
#!/bin/bash
echo -e "\n=== Hardware-Checks ==="
vcgencmd measure_temp
echo "throttled=$(vcgencmd get_throttled)"

echo -e "\n=== Service-Status ==="
systemctl is-active growcam.service && echo "growcam.service: aktiv" || echo "growcam.service: inaktiv"
systemctl is-active home-assistant@homeassistant && echo "home-assistant: aktiv" || echo "home-assistant: inaktiv"
systemctl is-active mosquitto && echo "mosquitto: aktiv" || echo "mosquitto: inaktiv"
systemctl is-active pigpiod && echo "pigpiod: aktiv" || echo "pigpiod: inaktiv"

echo -e "\n=== Sensorwerte ==="
if systemctl is-active pigpiod; then
  sudo python3 -c "
import pigpio
pi = pigpio.pi()
if pi.connected:
  print('Pigpio Version:', pi.get_pigpio_version())
  print('GPIO 4 (Beispiel):', pi.read(4))
else:
  print('Pigpio nicht verfügbar')
pi.stop()
"
else
  echo "Pigpio-Dienst nicht aktiv!"
fi
EOF

  sudo chmod +x /usr/local/bin/growbox-diag
  echo -e "${GREEN}✔ Diagnose-Tool installiert: 'growbox-diag'${NC}"
}

critical_error() {
  echo -e "${RED}>>> KRITISCHER FEHLER: $1${NC}"
  echo -e "${YELLOW}>>> Details im Log: $LOG_FILE${NC}"
  exit 1
}

# --- Hauptprogramm ---
main() {
  init
  prepare_system
  setup_sensors
  setup_camera
  final_check
  
  echo -e "${GREEN}\n=== Installation erfolgreich! ===${NC}"
  echo -e "Zugangslinks:"
  ip=$(hostname -I | awk '{print $1}')
  echo -e "Home Assistant: ${BLUE}http://$ip:8123${NC}"
  echo -e "Grafana:        ${BLUE}http://$ip:3000${NC}"
  echo -e "Kamera-Stream:  ${BLUE}http://$ip:8080${NC}"
  echo -e "MQTT Broker:    ${BLUE}mqtt://$ip:1883${NC}"
  echo -e "\nDiagnose: ${GREEN}growbox-diag${NC} oder ${GREEN}cat $LOG_FILE${NC}"
}

main
