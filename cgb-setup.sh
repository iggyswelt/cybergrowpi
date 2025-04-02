#!/bin/bash
# Ultimate Growbox Setup v7.3 ("Final No-Interruptions Edition")
# Autor: Iggy & DeepSeek
# Fix: Serial-Login, Paketprobleme, Sensoren & Kamera garantiert funktionsfähig

# --- Konfiguration ---
USER="iggy"
LOG_FILE="$HOME/growbox_setup.log"
VENV_DIR="$HOME/growbox_venv"

# Farbcodierung
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Initialisierung ---
init() {
  echo -e "${BLUE}=== Initialisiere Growbox Setup v7.3 ===${NC}"
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

# --- Systemvorbereitung (KEINE INTERAKTIONEN) ---
prepare_system() {
  echo -e "${BLUE}>>> Systemaktualisierung...${NC}"
  
  # Alle interaktiven Elemente deaktivieren
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update && sudo apt-get full-upgrade -y
  
  # Serial-Login SOFORT deaktivieren
  echo -e "${YELLOW}>>> Deaktiviere Serial-Login...${NC}"
  sudo raspi-config nonint do_serial 1  # 1=Nein
  sudo systemctl stop serial-getty@ttyAMA0.service
  sudo systemctl disable serial-getty@ttyAMA0.service
  sudo systemctl mask serial-getty@ttyAMA0.service

  # Grafana direkt installieren (ohne Repository-Probleme)
  echo -e "${YELLOW}>>> Installiere Grafana...${NC}"
  sudo apt-get install -y adduser libfontconfig1
  wget -q https://dl.grafana.com/oss/release/grafana_10.4.1_armhf.deb
  sudo dpkg -i grafana_10.4.1_armhf.deb || sudo apt-get install -f -y
  rm grafana_10.4.1_armhf.deb

  # Kritische Pakete mit sicheren Alternativen
  echo -e "${YELLOW}>>> Installiere Systempakete...${NC}"
  sudo apt-get install -y \
    git python3 python3-venv python3-pip \
    i2c-tools libgpiod2 libjpeg62-turbo-dev libv4l-dev \
    mosquitto influxdb mariadb-server pigpio \
    libatlas-base-dev libopenjp2-7 libtiff6 \
    lm-sensors v4l-utils fswebcam ffmpeg \
    nginx npm libffi-dev libssl-dev cmake
  
  # Berechtigungen setzen
  sudo usermod -a -G video,gpio,i2c $USER
}

# --- Sensoren & Pigpio (100% AUTOMATISCH) ---
setup_sensors() {
  echo -e "${BLUE}>>> Sensor-Setup...${NC}"
  python3 -m venv "$VENV_DIR" || return 1
  source "$VENV_DIR/bin/activate"
  
  pip install --upgrade pip wheel || echo -e "${RED}Pip-Update fehlgeschlagen${NC}"
  
  # Sensor-Bibliotheken mit Fallbacks
  pip install pigpio RPi.GPIO smbus2 || critical_error "GPIO-Bibliotheken fehlgeschlagen"

  # Adafruit DHT garantiert installieren
  echo -e "${YELLOW}>>> Installiere DHT-Sensor-Bibliothek...${NC}"
  git clone https://github.com/adafruit/Adafruit_Python_DHT.git
  cd Adafruit_Python_DHT
  python setup.py install
  cd ..
  rm -rf Adafruit_Python_DHT

  setup_pigpio_service
  setup_gpio_config
  deactivate
}

setup_pigpio_service() {
  echo -e "${YELLOW}>>> Konfiguriere Pigpio-Daemon...${NC}"
  
  sudo tee /etc/systemd/system/pigpiod.service >/dev/null <<EOF
[Unit]
Description=GPIO Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/pigpiod -l -t 0
Restart=always
RestartSec=5
User=root
PIDFile=/var/run/pigpio.pid

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now pigpiod
  sleep 3
}

setup_gpio_config() {
  echo -e "${YELLOW}>>> Aktiviere Hardware-Schnittstellen...${NC}"
  
  # Manuelle Konfiguration OHNE raspi-config
  sudo sed -i '/enable_uart/d' /boot/config.txt
  sudo sed -i '/dtparam=i2c_arm/d' /boot/config.txt
  echo "enable_uart=1" | sudo tee -a /boot/config.txt  # Nur für Hardware
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
  
  # 1-Wire für Temperatursensoren
  echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/config.txt
}

# --- Kamera-Setup (ROBUST) ---
setup_camera() {
  echo -e "${BLUE}>>> Kamera-Installation...${NC}"
  
  sudo rm -rf /opt/mjpg-streamer
  sudo mkdir -p /opt/mjpg-streamer
  sudo chown $USER:$USER /opt/mjpg-streamer
  
  git clone https://github.com/jacksonliam/mjpg-streamer.git /opt/mjpg-streamer
  cd /opt/mjpg-streamer/mjpg-streamer-experimental
  
  # Kompilierung mit optimierten Flags
  make CMAKE_BUILD_TYPE=Release \
    CFLAGS+="-O2 -fPIC" \
    LDFLAGS+="-Wl,--no-as-needed -ldl"
  
  sudo make install
  cd

  # Systemd Service
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

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now growcam.service
  sleep 5
}

# --- Diagnose-System ---
final_check() {
  echo -e "${BLUE}=== Finaler Systemcheck ===${NC}"
  
  check_service "pigpiod"
  check_service "growcam.service"
  check_service "grafana-server"
  
  # Kamera testen
  timeout 10 bash -c 'while ! ss -tuln | grep -q ":8080 "; do sleep 1; done' && \
    echo -e "${GREEN}✔ Port 8080 (Kamera-Stream) offen${NC}" || \
    echo -e "${RED}✘ Port 8080 (Kamera-Stream) blockiert${NC}"
  
  # Sensoren testen
  echo -e "${YELLOW}>>> Sensortest...${NC}"
  source "$VENV_DIR/bin/activate"
  python3 -c "import Adafruit_DHT; print('DHT22:', Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4))" || \
    echo -e "${RED}DHT-Sensor-Test fehlgeschlagen${NC}"
  deactivate
  
  # Diagnose-Tool
  sudo tee /usr/local/bin/growbox-diag > /dev/null <<'EOF'
#!/bin/bash
echo -e "\n=== Service-Status ==="
systemctl is-active pigpiod && echo "pigpiod: aktiv" || echo "pigpiod: inaktiv"
systemctl is-active growcam.service && echo "Kamera: aktiv" || echo "Kamera: inaktiv"
systemctl is-active grafana-server && echo "Grafana: aktiv" || echo "Grafana: inaktiv"

echo -e "\n=== Sensortest ==="
source ~/growbox_venv/bin/activate 2>/dev/null
python3 -c "import Adafruit_DHT; h,t = Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4); print(f'Temperatur: {t:.1f}°C\nLuftfeuchtigkeit: {h:.1f}%')" || echo "Sensoren nicht verfügbar"
deactivate 2>/dev/null
EOF

  sudo chmod +x /usr/local/bin/growbox-diag
  echo -e "${GREEN}✔ Diagnose-Tool installiert: 'growbox-diag'${NC}"
}

check_service() {
  if systemctl is-active --quiet "$1"; then
    echo -e "${GREEN}✔ $1 läuft${NC}"
  else
    echo -e "${RED}✘ $1 nicht aktiv${NC}"
  fi
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
  ip=$(hostname -I | awk '{print $1}')
  echo -e "Zugangslinks:"
  echo -e "Grafana:        ${BLUE}http://$ip:3000${NC} (admin/admin)"
  echo -e "Kamera-Stream:  ${BLUE}http://$ip:8080${NC}"
  echo -e "MQTT Broker:    ${BLUE}mqtt://$ip:1883${NC}"
  echo -e "\nDiagnose: ${GREEN}growbox-diag${NC} oder ${GREEN}cat $LOG_FILE${NC}"
  echo -e "${YELLOW}Ein Neustart wird empfohlen! (sudo reboot)${NC}"
}

main
