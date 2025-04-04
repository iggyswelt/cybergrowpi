#!/bin/bash

# Growbox Pi Setup Script - Ultimate Sensor Edition 2.0
# Autor: Iggy & DeepSeek
# Features: 
# - Installiert alle Sensor-Bibliotheken automatisch
# - Richtet virtuelle Umgebung für Python-Sensoren ein
# - Vollständige Fehlerbehandlung

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log-Datei
LOG_FILE="/home/$USER/growbox_setup.log"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Funktionen
error_exit() {
    echo -e "${RED}[FEHLER] $1${NC}" >&2
    echo -e "${YELLOW}Details im Log: $LOG_FILE${NC}"
    exit 1
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        error_exit "$1 ist nicht installiert"
    fi
}

# Sensor-spezifische Installation
install_sensor_libs() {
    print_header "Sensor-Bibliotheken Installation"
    
    # Virtuelle Umgebung erstellen
    VENV_DIR="/home/$USER/growbox_venv"
    python3 -m venv "$VENV_DIR" || error_exit "Virtuelle Umgebung konnte nicht erstellt werden"
    
    # Aktivieren und Pakete installieren
    source "$VENV_DIR/bin/activate" || error_exit "Aktivierung der virtuellen Umgebung fehlgeschlagen"
    
    # Kritische Pakete mit Version-Pinning
    pip install --upgrade pip wheel || error_exit "Pip Upgrade fehlgeschlagen"
    
    # Sensor-Bibliotheken
    SENSOR_LIBS=(
        "Adafruit-DHT==1.4.0"      # AM2301
        "bme680==1.1.1"            # BME680
        "RPi.GPIO==0.7.1"          # GPIO Zugriff
        "smbus2==0.4.1"            # I2C
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
    
    deactivate
}

# System-Update
system_update() {
    print_header "Systemaktualisierung"
    sudo apt-get update -y && sudo apt-get upgrade -y
    sudo apt-get autoremove -y
}

# Paketinstallation
install_packages() {
    print_header "Paketinstallation"
    local packages=(
        git python3 python3-pip python3-venv
        i2c-tools lm-sensors v4l-utils
        nginx mosquitto mosquitto-clients
        influxdb grafana fswebcam
        libjpeg62-turbo-dev libv4l-dev
        ffmpeg motion mariadb-server npm
    )
    
    sudo apt-get install -y "${packages[@]}" || error_exit "Paketinstallation fehlgeschlagen"
}

# mjpg-streamer Installation
install_mjpg_streamer() {
    print_header "mjpg-streamer Installation"
    local mjpg_dir="/opt/mjpg-streamer"
    
    if [ ! -f "/usr/local/bin/mjpg_streamer" ]; then
        sudo mkdir -p "$mjpg_dir"
        sudo chown $USER:$USER "$mjpg_dir"
        
        git clone https://github.com/jacksonliam/mjpg-streamer.git "$mjpg_dir" || error_exit "Klonen fehlgeschlagen"
        cd "$mjpg_dir/mjpg-streamer-experimental" || error_exit "Verzeichniswechsel fehlgeschlagen"
        
        make && sudo make install || error_exit "Kompilierung fehlgeschlagen"
        sudo ln -sf "$mjpg_dir/mjpg-streamer-experimental/mjpg_streamer" /usr/local/bin/
        
        sudo mkdir -p /usr/local/www
        sudo chown -R $USER:$USER /usr/local/www
    fi
}

# Home Assistant mit Fixes
install_homeassistant() {
    print_header "Home Assistant Installation"
    local ha_dir="/srv/homeassistant"
    
    if [ ! -d "$ha_dir" ]; then
        sudo useradd -rm homeassistant -G dialout,gpio,i2c,video || error_exit "Nutzeranlage fehlgeschlagen"
        sudo mkdir -p "$ha_dir" || error_exit "Verzeichnis erstellen fehlgeschlagen"
        sudo chown homeassistant:homeassistant "$ha_dir"
        
        sudo -u homeassistant python3 -m venv "$ha_dir" || error_exit "Venv erstellen fehlgeschlagen"
        
        # Kritische Pakete mit Version-Pinning
        sudo -u homeassistant -H -s <<EOF
source "$ha_dir/bin/activate"
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
WorkingDirectory=$ha_dir
ExecStart=$ha_dir/bin/hass -c "/home/homeassistant/.homeassistant"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable home-assistant@homeassistant
    fi
}

# Datenbank Setup
setup_mariadb() {
    print_header "MariaDB Konfiguration"
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS homeassistant CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "CREATE USER IF NOT EXISTS 'homeassistant'@'localhost' IDENTIFIED BY 'growbox123';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON homeassistant.* TO 'homeassistant'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
}

# Sensor-Test
test_sensors() {
    print_header "Sensor-Test"
    
    # Virtuelle Umgebung aktivieren
    source "/home/$USER/growbox_venv/bin/activate" || error_exit "Aktivierung der virtuellen Umgebung fehlgeschlagen"
    
    # Test-Script erstellen
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

    # Test ausführen
    python /tmp/sensor_test.py || error_exit "Sensor-Test fehlgeschlagen"
    deactivate
}

# Finale Checks
final_checks() {
    print_header "Abschlussprüfung"
    
    echo -e "\n${GREEN}=== Installierte Dienste ==="
    services=(
        growcam.service 
        home-assistant@homeassistant 
        grafana-server 
        influxdb 
        mosquitto
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✔ $service${NC}"
        else
            echo -e "${RED}✘ $service${NC}"
        fi
    done
    
    echo -e "\n${GREEN}=== Zugangslinks ==="
    local ip=$(hostname -I | awk '{print $1}')
    echo -e "Home Assistant: ${BLUE}http://$ip:8123${NC}"
    echo -e "Grafana:        ${BLUE}http://$ip:3000${NC}"
    echo -e "Kamera-Stream:  ${BLUE}http://$ip:8080/?action=stream${NC}"
    
    echo -e "\n${GREEN}=== Sensor-Virtualenv ==="
    echo -e "Aktivieren mit: ${BLUE}source ~/growbox_venv/bin/activate${NC}"
}

# Hauptinstallation
main() {
    print_header "Starte Growbox Setup"
    system_update
    install_packages
    install_sensor_libs
    install_mjpg_streamer
    setup_mariadb
    install_homeassistant
    test_sensors
    final_checks
    
    echo -e "\n${GREEN}=== Installation erfolgreich! ==="
    echo -e "Ein Neustart wird empfohlen.${NC}"
    echo -e "Logfile: ${BLUE}$LOG_FILE${NC}"
}

# Ausführung
main
