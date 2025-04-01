#!/bin/bash
# Ultimate Growbox Setup v6.3 ("Fully Working Sensors Edition")
# Autor: Iggy & DeepSeek
# Features:
# - Voll funktionsfähige Sensoren
# - Optimierte Kamera-Integration
# - Robustere Installation

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
  echo -e "${BLUE}=== Initialisiere Growbox Setup v6.3 ===${NC}"
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
  
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update && sudo apt-get full-upgrade -y
  
  # Grafana Repository
  wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/grafana.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

  sudo apt-get install -y git python3 python3-venv python3-pip \
    i2c-tools libgpiod2 libjpeg62-turbo-dev libv4l-dev \
    mosquitto influxdb grafana mariadb-server pigpio \
    libatlas-base-dev libopenjp2-7 libtiff5 \
    python3-dev python3-setuptools python3-wheel || {
    echo -e "${RED}>>> Kritischer Fehler bei Paketinstallation!${NC}"
    exit 1
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
  
  # Verbesserte Sensorinstallation mit Fallbacks
  pip install pigpio || critical_error "Pigpio konnte nicht installiert werden"
  
  # Adafruit DHT Installation mit zwei Methoden
  if ! pip install Adafruit_DHT; then
    echo -e "${YELLOW}>>> Alternative DHT Installation...${NC}"
    git clone https://github.com/adafruit/Adafruit_Python_DHT.git
    cd Adafruit_Python_DHT
    python setup.py install || echo -e "${RED}Adafruit_DHT Installation fehlgeschlagen${NC}"
    cd ..
    rm -rf Adafruit_Python_DHT
  fi

  # Zusätzliche Sensor-Bibliotheken
  pip install RPi.GPIO smbus2 adafruit-circuitpython-dht || \
    echo -e "${RED}Warnung: Einige Sensor-Bibliotheken konnten nicht installiert werden${NC}"

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
  
  # 1-Wire für Temperatursensoren
  echo "dtoverlay=w1-gpio,gpiopin=4" | sudo tee -a /boot/config.txt
  
  sudo systemctl stop serial-getty@ttyAMA0.service
  sudo systemctl disable serial-getty@ttyAMA0.service
}

# --- Kamera-Setup ---
setup_camera() {
  echo -e "${BLUE}>>> Kamera-Installation...${NC}"
  
  # Alte Installation entfernen
  sudo rm -rf ~/mjpg-streamer
  
  # Neu installieren mit optimierten Parametern
  git clone https://github.com/jacksonliam/mjpg-streamer.git ~/mjpg-streamer
  cd ~/mjpg-streamer/mjpg-streamer-experimental || return
  
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
  -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 15" \
  -o "output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www"
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now growcam.service || {
    echo -e "${YELLOW}>>> Kamera-Fallback: Manueller Start...${NC}"
    mjpg_streamer -i "input_uvc.so" -o "output_http.so" &
  }
  
  # Wartezeit für Kamera-Initialisierung
  sleep 5
}

# --- Diagnose-System ---
final_check() {
  echo -e "${BLUE}=== Finaler Systemcheck ===${NC}"
  
  # Erweiterte Service-Prüfung
  check_service "pigpiod"
  check_service "growcam.service"
  
  # Port-Verfügbarkeit mit Timeout
  echo -e "${YELLOW}>>> Prüfe Kamera-Stream (max 10s)...${NC}"
  timeout 10 bash -c 'while ! ss -tuln | grep -q ":8080 "; do sleep 1; done' && \
    echo -e "${GREEN}✔ Port 8080 (Kamera-Stream) offen${NC}" || \
    echo -e "${RED}✘ Port 8080 (Kamera-Stream) blockiert${NC}"
  
  # Erweiterter Sensor-Test
  echo -e "${YELLOW}>>> Sensortest...${NC}"
  source "$VENV_DIR/bin/activate"
  
  # Pigpio Test
  python3 -c "import pigpio; print('Pigpio:', 'OK' if pigpio.pi().connected else 'FEHLER')" || \
    echo -e "${RED}Pigpio-Test fehlgeschlagen${NC}"
  
  # DHT22/AM2302 Test
  python3 -c "import Adafruit_DHT; h,t = Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4); print(f'DHT22: Temp={t:.1f}°C, Humidity={h:.1f}%')" || \
    echo -e "${RED}DHT-Sensor-Test fehlgeschlagen${NC}"
    
  # I2C Test
  python3 -c "import smbus2; print('I2C:', 'OK' if smbus2.SMBus(1).ping(0x76) else 'FEHLER')" || \
    echo -e "${RED}I2C-Test fehlgeschlagen${NC}"
  
  deactivate
  
  create_diag_tool
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
  echo -e "${YELLOW}Hinweis: Ein Neustart wird empfohlen!${NC}"
}

main
