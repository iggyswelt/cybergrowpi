#!/usr/bin/env bash
# Growbox Setup v1.3 (Idiotensichere Edition für Webcam und Sensoren)
# Autor: Grok (xAI) - Optimiert für Home Assistant, BME680, AM2301 und Webcam

set -euo pipefail
USER=$(whoami)
LOG_FILE="$HOME/growbox_setup.log"
HA_VENV_DIR="$HOME/homeassistant_venv"
SENSOR_VENV_DIR="$HOME/sensor_venv"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HA_SERVICE=$(cat <<EOF
[Unit]
Description=Home Assistant Core
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=$HA_VENV_DIR/bin/hass -c "$HOME/.homeassistant"
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
)

CAM_SERVICE=$(cat <<EOF
[Unit]
Description=Growbox Webcam Service
After=network.target
[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d /dev/video0 -r 640x480 -f 15" -o "output_http.so -p 8080 -w /usr/local/share/mjpg-streamer/www"
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
)

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
check_root() { 
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
setup_sensors() {
    log "${BLUE}>> Sensor-Setup (BME680 und AM2301)...${NC}"
    python3 -m venv "$SENSOR_VENV_DIR"
    source "$SENSOR_VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install smbus2 bme680 paho-mqtt || { log "${RED}Fehler: Sensor-Bibliotheken fehlgeschlagen${NC}"; exit 1; }
    pip install Adafruit_DHT --force-pi || { log "${RED}Fehler: Adafruit_DHT Installation fehlgeschlagen${NC}"; exit 1; }
    deactivate
    cat <<EOF > "$HOME/sensor_mqtt.py"
#!/usr/bin/env python3
import time
import board
import adafruit_bme680
import Adafruit_DHT
import paho.mqtt.client as mqtt

DHT_PIN = 4
DHT_SENSOR = Adafruit_DHT.AM2301
MQTT_BROKER = "localhost"
MQTT_TOPIC_BME = "growbox/sensors/bme680"
MQTT_TOPIC_DHT = "growbox/sensors/am2301"

i2c = board.I2C()
bme680 = adafruit_bme680.Adafruit_BME680_I2C(i2c)
client = mqtt.Client()
client.connect(MQTT_BROKER, 1883, 60)

while True:
    temp = bme680.temperature
    hum = bme680.humidity
    client.publish(MQTT_TOPIC_BME, f"temp={temp},hum={hum}")
    humidity, temperature = Adafruit_DHT.read_retry(DHT_SENSOR, DHT_PIN)
    if humidity is not None and temperature is not None:
        client.publish(MQTT_TOPIC_DHT, f"temp={temperature},hum={humidity}")
    time.sleep(60)
EOF
    chmod +x "$HOME/sensor_mqtt.py"
    cat <<EOF | sudo tee /etc/systemd/system/growsensor.service
[Unit]
Description=Growbox Sensor MQTT Service
After=network.target mosquitto.service
[Service]
Type=simple
User=$USER
ExecStart=$SENSOR_VENV_DIR/bin/python3 $HOME/sensor_mqtt.py
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now growsensor.service
    log "${GREEN}Sensor-Setup abgeschlossen${NC}"
}
setup_webcam() {
    log "${BLUE}>> Webcam-Setup...${NC}"
    git clone https://github.com/jacksonliam/mjpg-streamer.git "$HOME/mjpg-streamer" || { log "${RED}Fehler: MJPG-Streamer klonen fehlgeschlagen${NC}"; exit 1; }
    cd "$HOME/mjpg-streamer/mjpg-streamer-experimental"
    make && sudo make install || { log "${RED}Fehler: Webcam-Kompilierung fehlgeschlagen${NC}"; exit 1; }
    cd "$HOME"
    echo "$CAM_SERVICE" | sudo tee /etc/systemd/system/growcam.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now growcam.service
    log "${GREEN}Webcam-Setup abgeschlossen${NC}"
}
setup_homeassistant() {
    log "${BLUE}>> Home Assistant Setup...${NC}"
    python3 -m venv "$HA_VENV_DIR"
    source "$HA_VENV_DIR/bin/activate"
    pip install --upgrade pip
    pip install homeassistant || { log "${RED}Fehler: Home Assistant Installation fehlgeschlagen${NC}"; exit 1; }
    deactivate
    echo "$HA_SERVICE" | sudo tee /etc/systemd/system/home-assistant.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now home-assistant.service
    log "${GREEN}Home Assistant Setup abgeschlossen${NC}"
}

main() {
    log "${GREEN}=== Growbox Setup v1.3 Start ===${NC}"
    check_root
    enable_i2c
    update_system
    install_dependencies
    setup_sensors
    setup_webcam
    setup_homeassistant
    ip=$(hostname -I | awk '{print $1}')
    log "${GREEN}=== Installation abgeschlossen! ===${NC}"
    log "Home Assistant: ${BLUE}http://$ip:8123${NC}"
    log "Webcam-Stream: ${BLUE}http://$ip:8080${NC}"
    log "Sensor-Daten via MQTT: growbox/sensors/bme680 und growbox/sensors/am2301"
}

main
