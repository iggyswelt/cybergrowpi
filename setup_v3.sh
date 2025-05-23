#!/usr/bin/env bash
# Growbox Setup v7.5 (Benutzerfreundliche Edition)
# Autor: Iggy & Gemini (optimiert für einfache Installation)

# --- Globale Einstellungen ---
set -euo pipefail
USER="$USER" # Aktuellen Benutzer verwenden
LOG_FILE="$HOME/growbox_setup.log"
VENV_DIR="$HOME/growbox_venv"
GRAFANA_VERSION="10.4.1"

# --- Farbcodierung ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Systemd-Dienst-Vorlagen ---
PIGPIOD_SERVICE=$(cat <<EOF
[Unit]
Description=GPIO Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/pigpiod -l -t 0
Restart=always
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=10
User=root
PIDFile=/var/run/pigpio.pid

[Install]
WantedBy=multi-user.target
EOF
)

# --- Funktionen ---
init() {
  echo -e "${BLUE}=== Growbox Setup v7.5 Initialisierung ===${NC}" | tee -a "$LOG_FILE"
  trap "cleanup" EXIT
  check_root
  hardware_checks
  kill_conflicting_processes
}

cleanup() {
  echo -e "${BLUE}=== Aufräumen... ===${NC}" | tee -a "$LOG_FILE"
  sudo systemctl restart pigpiod 2>/dev/null || true
  exit 0
}

check_root() {
  if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Fehler: Nicht als root ausführen! Bitte als normaler Benutzer ausführen.${NC}" | tee -a "$LOG_FILE"
    exit 1
  fi
}

hardware_checks() {
  echo -e "${YELLOW}>>> Hardware-Checks...${NC}" | tee -a "$LOG_FILE"
  lsmod | grep -q i2c_dev || critical_error "I2C-Treiber nicht geladen. Bitte 'sudo raspi-config' -> Interface -> I2C aktivieren."
  i2cdetect -y 1 || critical_error "I2C-Bus nicht erreichbar. Überprüfe die I2C-Verbindung."
  vcgencmd get_throttled | grep -q "throttled=0x0" || echo -e "${YELLOW}Warnung: Under-voltage erkannt. Überprüfe die Stromversorgung.${NC}" | tee -a "$LOG_FILE"
}

kill_conflicting_processes() {
  echo -e "${YELLOW}>>> Beende konkurrierende Prozesse...${NC}" | tee -a "$LOG_FILE"
  sudo pkill pigpiod || true
  sudo pkill mjpg_streamer || true
  sudo rm -f /var/run/pigpio.pid
}

prepare_system() {
  echo -e "${BLUE}>>> Systemaktualisierung...${NC}" | tee -a "$LOG_FILE"
  export DEBIAN_FRONTEND=noninteractive

  # Grafana Repository-Sicherheit
  echo -e "${YELLOW}>>> Grafana-Repositorien konfigurieren...${NC}" | tee -a "$LOG_FILE"
  sudo rm -f /usr/share/keyrings/grafana* /etc/apt/sources.list.d/grafana.list
  sudo mkdir -p /usr/share/keyrings
  curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/grafana.gpg >/dev/null || critical_error "GPG-Key-Import fehlgeschlagen"
  echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list || critical_error "Repository-Konfiguration fehlgeschlagen"

  sudo apt-get update && sudo apt-get full-upgrade -y

  echo -e "${YELLOW}>>> Deaktiviere Serial-Login...${NC}" | tee -a "$LOG_FILE"
  sudo raspi-config nonint do_serial 1 # Abfrage vermeiden
  sudo systemctl mask serial-getty@ttyAMA0.service

  echo -e "${YELLOW}>>> Installiere Grafana ${GRAFANA_VERSION}...${NC}" | tee -a "$LOG_FILE"
  sudo apt-get install -y adduser libfontconfig1
  wget -q "https://dl.grafana.com/oss/release/grafana_${GRAFANA_VERSION}_armhf.deb" || critical_error "Grafana-Download fehlgeschlagen"
  sudo dpkg -i "grafana_${GRAFANA_VERSION}_armhf.deb" || sudo apt-get install -f -y
  rm "grafana_${GRAFANA_VERSION}_armhf.deb"

  echo -e "${YELLOW}>>> Installiere Systempakete...${NC}" | tee -a "$LOG_FILE"
  sudo apt-get install -y \
    git python3 python3-venv python3-pip \
    i2c-tools libgpiod2 libjpeg62-turbo-dev \
    mosquitto influxdb influxdb-cli mariadb-server pigpio \
    libatlas-base-dev libopenjp2-7 libtiff6 \
    lm-sensors v4l-utils fswebcam ffmpeg \
    nginx npm libffi-dev libssl-dev cmake

  sudo usermod -a -G video,gpio,i2c "$USER"
}

setup_sensors() {
  echo -e "${BLUE}>>> Sensor-Setup...${NC}" | tee -a "$LOG_FILE"
  python3 -m venv "$VENV_DIR" || critical_error "Python-VENV fehlgeschlagen"
  source "$VENV_DIR/bin/activate"

  pip install --upgrade pip wheel || critical_error "Pip-Update fehlgeschlagen"
  pip install pigpio RPi.GPIO smbus2 bme680 paho-mqtt || critical_error "GPIO- und Sensor-Bibliotheken fehlgeschlagen"

  echo -e "${YELLOW}>>> Installiere DHT-Sensor-Bibliothek...${NC}" | tee -a "$LOG_FILE"
  git clone https://github.com/adafruit/Adafruit_Python_DHT.git || critical_error "DHT-Clone fehlgeschlagen"
  cd Adafruit_Python_DHT
  python setup.py install || critical_error "DHT-Installation fehlgeschlagen"
  cd ..
  rm -rf Adafruit_Python_DHT

  setup_pigpio_service
  deactivate

  echo -e "${YELLOW}>>> Starte BME680 Sensor Skript im Hintergrund...${NC}" | tee -a "$LOG_FILE"
  nohup python3 "$HOME/bme680_mqtt.py" &
  echo -e "${GREEN}>>> BME680 Sensor Skript gestartet. Daten werden an MQTT Topic '${BLUE}growbox/sensors/bme680${GREEN}' gesendet.${NC}" | tee -a "$LOG_FILE"
}

setup_pigpio_service() {
  echo -e "${YELLOW}>>> Konfiguriere Pigpio-Daemon...${NC}" | tee -a "$LOG_FILE"
  echo "$PIGPIOD_SERVICE" | sudo tee /etc/systemd/system/pigpiod.service >/dev/null
  sudo chmod 644 /etc/systemd/system/pigpiod.service
  sudo chown root:root /etc/systemd/system/pigpiod.service

  sudo systemctl daemon-reload
  sudo systemctl enable --now pigpiod
  sleep 3
  sudo systemctl is-active pigpiod || critical_error "Pigpio-Dienst fehlgeschlagen"
}

setup_camera() {
  echo -e "${BLUE}>>> Kamera-Installation...${NC}" | tee -a "$LOG_FILE"
  sudo rm -rf /opt/mjpg-streamer
  sudo mkdir -p /opt/mjpg-streamer
  sudo chown "$USER:$USER" /opt/mjpg-streamer

  git clone https://github.com/jacksonliam/mjpg-streamer.git /opt/mjpg-streamer || critical_error "MJPG-Streamer-Clone fehlgeschlagen"
  cd /opt/mjpg-streamer/mjpg-streamer-experimental

  make CMAKE_BUILD_TYPE=Release \
    CFLAGS+="-O2 -fPIC" \
    LDFLAGS+="-Wl,--no-as-needed -ldl" || critical_error "Kamera-Kompilierung fehlgeschlagen"

  sudo make install || critical_error "Kamera-Installation fehlgeschlagen"
  cd ..

  sudo tee /etc/systemd/system/growcam.service >/dev/null <<EOF
[Unit]
Description=Growbox Camera Service
After=network.target

[Service]
Type=simple
User=$USER
Environment="LD_LIBRARY_PATH=/usr/local/lib"
ExecStart=/usr/local/bin/mjpg_streamer \
    -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 15 -n" \
    -o "output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www"
Restart=always
RestartSec=5s
TimeoutStartSec=30
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now growcam.service
  sleep 5
  sudo systemctl is-active growcam.service || critical_error "Kameradienst fehlgeschlagen"
}

# --- Hauptprogramm ---
main() {
  init
  prepare_system
  setup_sensors
  setup_camera

  echo -e "${GREEN}\n=== Installation erfolgreich! ===${NC}" | tee -a "$LOG_FILE"
  ip=$(hostname -I | awk '{print $1}')
  echo -e "Zugangslinks:" | tee -a "$LOG_FILE"
  echo -e "Grafana:    ${BLUE}http://$ip:3000${NC} (admin/admin)" | tee -a "$LOG_FILE"
  echo -e "Kamera-Stream: ${BLUE}http://$ip:8080${NC}" | tee -a "$LOG_FILE"
  echo -e "\nDiagnose: ${GREEN}journalctl -u growcam.service${NC}" | tee -a "$LOG_FILE"
}

critical_error() {
  echo -e "${RED}>>> KRITISCHER FEHLER: $1${NC}" | tee -a "$LOG_FILE"
  echo -e "${YELLOW}>>> Details im Log: $LOG_FILE${NC}" | tee -a "$LOG_FILE"
  exit 1
}

main
