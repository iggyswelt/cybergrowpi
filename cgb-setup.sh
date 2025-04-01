#!/bin/bash
# Ultimate Growbox Setup v6.0 ("Perfect Fusion Edition")
# Autor: Iggy & DeepSeek
# Features:
# - Kombiniert beste Sensor- und Kamera-Implementierungen
# - Vollständige Fehlerbehandlung
# - Optimierte Performance
# - Automatische Problembehebung

# --- Konfiguration ---
USER="iggy"
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
  echo -e "${BLUE}=== Initialisiere Growbox Setup v6.0 ===${NC}"
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
  sudo pkill motion || true
  sudo rm -f /var/run/pigpio.pid
}

# --- Systemvorbereitung ---
prepare_system() {
  echo -e "${BLUE}>>> Systemaktualisierung...${NC}"
  
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update && sudo apt-get full-upgrade -y
  
  # Grafana Repository
  wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/grafana.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

  # Pakete mit alternativen Abhängigkeiten
  sudo apt-get install -y git python3 python3-venv python3-pip \
    i2c-tools libgpiod2 libjpeg62-turbo-dev libv4l-dev \
    mosquitto influxdb grafana mariadb-server pigpio \
    libatlas-base-dev libopenjp2-7 libtiff-dev \  # Geändert von libtiff5 zu libtiff-dev
    lm-sensors v4l-utils fswebcam ffmpeg motion \
    nginx npm || {
    echo -e "${RED}>>> Kritischer Fehler bei Paketinstallation!${NC}"
    echo -e "${YELLOW}>>> Versuche alternative Paketquellen...${NC}"
    
    # Fallback für ältere Debian-Versionen
    sudo apt-get install -y libtiff5 || sudo apt-get install -y libtiff4
    sudo apt-get install -y --fix-broken
  }

  # Video-Gruppe für Kamera-Zugriff
  sudo usermod -a -G video $USER
}

# --- Sensoren & Pigpio ---
setup_sensors() {
  echo -e "${BLUE}>>> Sensor-Setup...${NC}"
  python3 -m venv "$VENV_DIR" || return 1
  source "$VENV_DIR/bin/activate"
  
  pip install --upgrade pip wheel || critical_error "Pip-Update fehlgeschlagen"
  
  # Kritische Sensor-Bibliotheken mit Version-Pinning
  SENSOR_LIBS=(
    "Adafruit-DHT==1.4.0"      # AM2301
    "bme680==1.1.1"            # BME680
    "RPi.GPIO==0.7.1"          # GPIO Zugriff
    "smbus2==0.4.1"            # I2C
    "pigpio==1.78"             # GPIO-Zugriff
    "python-dotenv==1.0.0"     # Konfiguration
  )
  
  for lib in "${SENSOR_LIBS[@]}"; do
    echo -e "${YELLOW}Installiere $lib...${NC}"
    pip install "$lib" || echo -e "${RED}Warnung: $lib konnte nicht installiert werden${NC}"
  done

  # 1-Wire für DS18B20 aktivieren
  if ! grep -q "dtoverlay=w1-gpio" /boot/config.txt; then
    echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/config.txt > /dev/null
    echo -e "${GREEN}1-Wire für DS18B20 aktiviert${NC}"
  fi

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
  sudo systemctl enable --now pigpiod || {
    echo -e "${YELLOW}>>> Fallback: Manueller Pigpio-Start...${NC}"
    sudo pigpiod -l -t 0
  }
  sleep 3  # Wartezeit für stabilen Start
}

setup_gpio_config() {
  echo -e "${YELLOW}>>> Aktiviere Hardware-Schnittstellen...${NC}"
  
  sudo sed -i '/enable_uart/d' /boot/config.txt
  sudo sed -i '/dtparam=i2c_arm/d' /boot/config.txt
  echo "enable_uart=1" | sudo tee -a /boot/config.txt
  echo "dtparam=i2c_arm=on" | sudo tee -a /boot/config.txt
  
  sudo systemctl stop serial-getty@ttyAMA0.service
  sudo systemctl disable serial-getty@ttyAMA0.service
}

# --- Kamera-Setup (optimierte Version) ---
setup_camera() {
  echo -e "${BLUE}>>> Kamera-Installation...${NC}"
  
  # Alte Installation entfernen
  sudo rm -rf /opt/mjpg-streamer
  
  # Neu installieren mit optimierten Parametern
  sudo mkdir -p /opt/mjpg-streamer
  sudo chown $USER:$USER /opt/mjpg-streamer
  git clone https://github.com/jacksonliam/mjpg-streamer.git /opt/mjpg-streamer
  cd /opt/mjpg-streamer/mjpg-streamer-experimental || return
  
  # Fix für Kompilierungsprobleme
  sudo sed -i 's/PLUGINS += input_gspcav1.so//' Makefile
  sudo sed -i 's/PLUGINS += output_autofocus.so//' Makefile
  
  make || {
    echo -e "${YELLOW}>>> Erster Kompilierungsversuch fehlgeschlagen, versuche es mit Alternativen...${NC}"
    sudo apt-get install -y cmake libjpeg9-dev
    make clean && make
  }
  
  sudo make install
  cd

  # Service mit verbesserten Parametern
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
  sudo systemctl enable --now growcam.service || {
    echo -e "${YELLOW}>>> Kamera-Fallback: Manueller Start...${NC}"
    /usr/local/bin/mjpg_streamer -i "input_uvc.so" -o "output_http.so" &
  }
  
  # Wartezeit für Kamera-Initialisierung
  sleep 5
}

# --- Home Assistant Installation ---
setup_homeassistant() {
  echo -e "${BLUE}>>> Home Assistant Installation...${NC}"
  
  if [ ! -d "$HA_DIR" ]; then
    sudo useradd -rm homeassistant -G dialout,gpio,i2c,video || critical_error "Nutzeranlage fehlgeschlagen"
    sudo mkdir -p "$HA_DIR" || critical_error "Verzeichnis erstellen fehlgeschlagen"
    sudo chown homeassistant:homeassistant "$HA_DIR"
    
    sudo -u homeassistant python3 -m venv "$HA_DIR" || critical_error "Venv erstellen fehlgeschlagen"
    
    # Kritische Pakete mit Version-Pinning
    sudo -u homeassistant -H -s <<EOF
source "$HA_DIR/bin/activate"
pip install --upgrade pip wheel
pip install "josepy==1.13.0" "acme==2.8.0" "certbot==2.8.0"
pip install homeassistant
EOF
    
    # Systemd Service
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

    sudo systemctl daemon-reload
    sudo systemctl enable home-assistant@homeassistant
    sudo systemctl start home-assistant@homeassistant
  fi
}

# --- Datenbank Setup ---
setup_database() {
  echo -e "${BLUE}>>> Datenbank-Konfiguration...${NC}"
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS homeassistant CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sudo mysql -e "CREATE USER IF NOT EXISTS 'homeassistant'@'localhost' IDENTIFIED BY 'growbox123';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON homeassistant.* TO 'homeassistant'@'localhost';"
  sudo mysql -e "FLUSH PRIVILEGES;"
}

# --- Diagnose-System ---
final_check() {
  echo -e "${BLUE}=== Finaler Systemcheck ===${NC}"
  
  # Erweiterte Service-Prüfung
  check_service "pigpiod"
  check_service "growcam.service"
  check_service "home-assistant@homeassistant"
  check_service "grafana-server"
  check_service "influxdb"
  check_service "mosquitto"
  
  # Port-Verfügbarkeit mit Timeout
  echo -e "${YELLOW}>>> Prüfe Kamera-Stream (max 10s)...${NC}"
  timeout 10 bash -c 'while ! ss -tuln | grep -q ":8080 "; do sleep 1; done' && \
    echo -e "${GREEN}✔ Port 8080 (Kamera-Stream) offen${NC}" || \
    echo -e "${RED}✘ Port 8080 (Kamera-Stream) blockiert${NC}"
  
  # Sensor-Test mit Fehlerbehandlung
  echo -e "${YELLOW}>>> Sensortest...${NC}"
  source "$VENV_DIR/bin/activate"
  python3 -c "import pigpio; print('Pigpio:', 'OK' if pigpio.pi().connected else 'FEHLER')" || \
    echo -e "${RED}Pigpio-Test fehlgeschlagen${NC}"
  
  # Erweiterter Sensor-Test
  cat > /tmp/sensor_test.py <<'EOF'
import Adafruit_DHT, bme680, os, glob, time

print("=== AM2301 Test ===")
humidity, temp = Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4)
print(f"Temp: {temp:.1f}°C, Feuchtigkeit: {humidity:.1f}%")

print("\n=== BME680 Test ===")
bme = bme680.BME680()
if bme.get_sensor_data():
    print(f"Temp: {bme.data.temperature:.1f}°C, Druck: {bme.data.pressure:.1f}hPa")

print("\n=== DS18B20 Test ===")
devices = glob.glob("/sys/bus/w1/devices/28-*")
for device in devices:
    with open(f"{device}/temperature") as f:
        temp = float(f.read()) / 1000.0
    print(f"Sensor {device.split('/')[-1]}: {temp:.1f}°C")
EOF

  python3 /tmp/sensor_test.py || echo -e "${RED}Sensor-Test fehlgeschlagen${NC}"
  deactivate
  
  create_diag_tool
}

check_service() {
  if systemctl is-active --quiet "$1"; then
    echo -e "${GREEN}✔ $1 läuft${NC}"
  else
    echo -e "${RED}✘ $1 nicht aktiv${NC}"
  fi
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
import Adafruit_DHT, bme680, os, glob
print('AM2301:', Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4))
bme = bme680.BME680()
print('BME680:', bme.get_sensor_data() and f'{bme.data.temperature:.1f}°C')
print('DS18B20:', [f'{float(open(f+"/temperature").read())/1000:.1f}°C' for f in glob.glob('/sys/bus/w1/devices/28-*')])
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
  setup_database
  setup_homeassistant
  final_check
  
  echo -e "${GREEN}\n=== Installation erfolgreich! ===${NC}"
  ip=$(hostname -I | awk '{print $1}')
  echo -e "Zugangslinks:"
  echo -e "Home Assistant: ${BLUE}http://$ip:8123${NC} (erster Start kann einige Minuten dauern)"
  echo -e "Grafana:        ${BLUE}http://$ip:3000${NC} (admin/admin)"
  echo -e "Kamera-Stream:  ${BLUE}http://$ip:8080/?action=stream${NC}"
  echo -e "MQTT Broker:    ${BLUE}mqtt://$ip:1883${NC}"
  echo -e "\nDiagnose: ${GREEN}growbox-diag${NC} oder ${GREEN}cat $LOG_FILE${NC}"
  echo -e "${YELLOW}Ein Neustart wird empfohlen!${NC}"
}

main
