#!/bin/bash
# Ultimate Growbox Setup Script v3.0 ("Unkillable")
# Autor: Iggy & DeepSeek
# Features: Selbstheilend, Mehrfachausführungssicher, Automatische Diagnose

# --- Konfiguration ---
USER="Iggy"
LOG_DIR="$HOME/growbox_logs"
VENV_DIR="$HOME/growbox_venv"
HA_DIR="/srv/homeassistant"
MJPG_DIR="/opt/mjpg-streamer"

# Farben
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# --- Initialisierung ---
init() {
  mkdir -p $LOG_DIR
  exec > >(tee "$LOG_DIR/setup.log") 2>&1
  trap "echo -e '${RED}Script abgebrochen!${NC}'; exit 1" SIGINT
  echo -e "${BLUE}=== Starte Growbox Setup v3.0 ===${NC}"
}

# --- Systemvorbereitung ---
prepare_system() {
  echo -e "${BLUE}>>> Systemaktualisierung...${NC}"
  sudo apt update && sudo apt full-upgrade -y
  sudo apt autoremove -y --purge

  echo -e "${BLUE}>>> Basis-Pakete installieren...${NC}"
  sudo apt install -y git python3 python3-pip python3-venv i2c-tools \
    libjpeg62-turbo-dev libv4l-dev ffmpeg v4l-utils mosquitto \
    influxdb grafana-enterprise mariadb-server npm
}

# --- Hardware-Interfaces ---
enable_hardware() {
  echo -e "${BLUE}>>> Aktiviere Hardware-Schnittstellen...${NC}"
  sudo raspi-config nonint do_i2c 0
  sudo raspi-config nonint do_camera 0
  sudo sed -i '/dtoverlay=w1-gpio/d' /boot/config.txt
  echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/config.txt
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
}

# --- Sensor-Installation (Selbstheilend) ---
install_sensors() {
  echo -e "${BLUE}>>> Installiere Sensor-Bibliotheken...${NC}"
  python3 -m venv $VENV_DIR || { echo -e "${RED}Venv-Fehler!${NC}"; return 1; }
  source $VENV_DIR/bin/activate

  # Adafruit_DHT mit Fallback-Lösung
  if ! pip install Adafruit-DHT --install-option="--force-pi"; then
    echo -e "${YELLOW}Fallback: Installiere von GitHub...${NC}"
    pip install git+https://github.com/adafruit/Adafruit_Python_DHT.git
  fi

  # BME680 mit alternativem I2C-Kanal
  pip install smbus2 bme680 || echo -e "${YELLOW}BME680-Installation fehlgeschlagen${NC}"

  deactivate
}

# --- Kamera-Systemd-Service ---
setup_camera() {
  echo -e "${BLUE}>>> Konfiguriere Kamera-Service...${NC}"
  if [ ! -d "$MJPG_DIR" ]; then
    git clone https://github.com/jacksonliam/mjpg-streamer.git $MJPG_DIR
    cd $MJPG_DIR/mjpg-streamer-experimental
    make && sudo make install
  fi

  sudo tee /etc/systemd/system/growcam.service > /dev/null <<EOF
[Unit]
Description=Growbox Camera Service
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d /dev/video0" -o "output_http.so -p 8080"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
}

# --- Home Assistant Installation ---
install_ha() {
  echo -e "${BLUE}>>> Installiere Home Assistant...${NC}"
  if ! id "homeassistant" &>/dev/null; then
    sudo useradd -rm homeassistant -G dialout,gpio,i2c,video
    sudo mkdir -p $HA_DIR
    sudo chown homeassistant:homeassistant $HA_DIR
  fi

  sudo -u homeassistant python3 -m venv $HA_DIR || return 1
  sudo -u homeassistant -H -s <<EOF
source $HA_DIR/bin/activate
pip install --upgrade pip wheel
pip install "josepy==1.13.0" "acme==2.8.0" "certbot==2.8.0" homeassistant
EOF

  sudo tee /etc/systemd/system/home-assistant@homeassistant.service > /dev/null <<EOF
[Unit]
Description=Home Assistant
After=network.target mariadb.service

[Service]
Type=simple
User=homeassistant
WorkingDirectory=$HA_DIR
ExecStart=$HA_DIR/bin/hass -c "/home/homeassistant/.homeassistant"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable home-assistant@homeassistant
}

# --- Datenbank-Setup ---
setup_database() {
  echo -e "${BLUE}>>> Konfiguriere MariaDB...${NC}"
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS homeassistant;"
  sudo mysql -e "CREATE USER IF NOT EXISTS 'homeassistant'@'localhost' IDENTIFIED BY 'growbox123';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON homeassistant.* TO 'homeassistant'@'localhost';"
  sudo mysql -e "FLUSH PRIVILEGES;"
}

# --- Diagnose-Script ---
create_diagnostic() {
  echo -e "${BLUE}>>> Erstelle Diagnose-Script...${NC}"
  sudo tee /usr/local/bin/growbox-diagnose > /dev/null <<'EOF'
#!/bin/bash
# Growbox Diagnose-Script
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== Hardware-Checks ===${NC}"
v4l2-ctl --list-devices | grep -q video0 && echo -e "${GREEN}✔ Kamera erkannt${NC}" || echo -e "${RED}✘ Kamera nicht gefunden${NC}"
i2cdetect -y 1 | grep -q 76 && echo -e "${GREEN}✔ BME680 erkannt (0x76)${NC}" || echo -e "${RED}✘ BME680 nicht gefunden${NC}"
ls /sys/bus/w1/devices/28-* &>/dev/null && echo -e "${GREEN}✔ DS18B20 erkannt${NC}" || echo -e "${RED}✘ DS18B20 nicht gefunden${NC}"

echo -e "\n${BLUE}=== Service-Status ===${NC}"
services=("growcam.service" "home-assistant@homeassistant" "mosquitto" "grafana-server" "influxdb")
for service in "${services[@]}"; do
  if systemctl is-active $service >/dev/null; then
    echo -e "${GREEN}✔ $service${NC}"
  else
    echo -e "${RED}✘ $service${NC}"
  fi
done

echo -e "\n${BLUE}=== Netzwerk-Info ===${NC}"
ip=$(hostname -I | awk '{print $1}')
echo -e "Home Assistant: ${BLUE}http://$ip:8123${NC}"
echo -e "Grafana:        ${BLUE}http://$ip:3000${NC}"
echo -e "Kamera-Stream:  ${BLUE}http://$ip:8080/?action=stream${NC}"

echo -e "\n${BLUE}=== Sensorwerte ===${NC}"
$HOME/growbox_venv/bin/python3 -c "
import Adafruit_DHT, bme680, glob, time
print('AM2301:', Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4)[1:])
try:
  bme = bme680.BME680(i2c_addr=0x76)
  print('BME680:', bme.data.temperature if bme.get_sensor_data() else 'Fehler')
except Exception as e:
  print('BME680 Fehler:', str(e))
print('DS18B20:', [round(open(f+'/temperature').read())/1000 for f in glob.glob('/sys/bus/w1/devices/28-*')])
"
EOF

  sudo chmod +x /usr/local/bin/growbox-diagnose
}

# --- Hauptroutine ---
main() {
  init
  prepare_system
  enable_hardware
  install_sensors
  setup_camera
  setup_database
  install_ha
  create_diagnostic

  echo -e "${GREEN}\n=== Installation abgeschlossen ===${NC}"
  echo -e "Führe folgenden Befehl für Systemprüfung aus:"
  echo -e "${BLUE}growbox-diagnose${NC}"
  echo -e "Systemneustart empfohlen!"
}

# --- Ausführung ---
main
