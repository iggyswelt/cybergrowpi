#!/bin/bash

# Growbox Pi Setup Script - 100% Lokal (Version 5.0)
# Autor: Iggy mit ChatGPT
# GitHub: https://github.com/yourusername/growbox-pi-local

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log-Datei
LOG_FILE="/var/log/growbox_setup.log"
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Funktionen
error_exit() {
    echo -e "${RED}[FEHLER] $1${NC}" >&2
    echo -e "${YELLOW}Log: $LOG_FILE${NC}"
    exit 1
}

status_check() {
    if [ $? -ne 0 ]; then
        error_exit "$1"
    else
        echo -e "${GREEN}[OK]${NC} $2"
    fi
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# System-Update
print_header "1. Systemupdate"
sudo apt-get update -y || error_exit "Update fehlgeschlagen"
sudo apt-get upgrade -y || error_exit "Upgrade fehlgeschlagen"
sudo apt-get autoremove -y

# Basispakete
print_header "2. Installiere Basispakete"
BASE_PACKAGES=(
    git python3 python3-pip python3-venv
    i2c-tools lm-sensors v4l-utils
    nginx mosquitto mosquitto-clients
    influxdb libjpeg62-turbo-dev libv4l-dev
    ffmpeg motion mariadb-server
)

sudo apt-get install -y "${BASE_PACKAGES[@]}" || error_exit "Paketinstallation fehlgeschlagen"

# Grafana (lokal)
curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
sudo apt-get update && sudo apt-get install -y grafana || error_exit "Grafana-Installation fehlgeschlagen"

# Hardware aktivieren
print_header "3. Aktiviere Schnittstellen"
sudo raspi-config nonint do_camera 0 || error_exit "Kamera konnte nicht aktiviert werden"
sudo raspi-config nonint do_i2c 0 || error_exit "I2C konnte nicht aktiviert werden"
sudo raspi-config nonint do_spi 0 || error_exit "SPI konnte nicht aktiviert werden"
sudo raspi-config nonint do_onewire 0 || error_exit "1-Wire konnte nicht aktiviert werden"

# mjpg-streamer (lokal)
print_header "4. Installiere mjpg-streamer"
if [ ! -f "/usr/local/bin/mjpg_streamer" ]; then
    MJPG_DIR="/opt/mjpg-streamer"
    sudo mkdir -p "$MJPG_DIR"
    sudo chown "$USER":"$USER" "$MJPG_DIR"
    
    git clone https://github.com/jacksonliam/mjpg-streamer.git "$MJPG_DIR" || error_exit "Klonen fehlgeschlagen"
    cd "$MJPG_DIR/mjpg-streamer-experimental" || error_exit "Verzeichnis nicht gefunden"
    make clean && make || error_exit "Kompilierung fehlgeschlagen"
    sudo make install || error_exit "Installation fehlgeschlagen"
    sudo ln -sf "$MJPG_DIR/mjpg-streamer-experimental/mjpg_streamer" /usr/local/bin/
    
    sudo mkdir -p /usr/local/www
    sudo chown -R "$USER":"$USER" /usr/local/www
fi

# Kamera-Service
print_header "5. Kamera-Service"
sudo tee /etc/systemd/system/growcam.service > /dev/null <<EOF
[Unit]
Description=Growbox Camera Stream
After=network.target

[Service]
User=$USER
ExecStart=/usr/local/bin/mjpg_streamer \\
  -i "input_uvc.so -d /dev/video0 -r 640x480 -f 10 -q 80 -n" \\
  -o "output_http.so -w /usr/local/www -p 8080"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable growcam.service
sudo systemctl start growcam.service

# MariaDB für Home Assistant
print_header "6. MariaDB einrichten"
sudo mysql -e "CREATE DATABASE homeassistant CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || error_exit "Datenbank konnte nicht erstellt werden"
sudo mysql -e "CREATE USER 'homeassistant'@'localhost' IDENTIFIED BY 'dein_sicheres_passwort';" || error_exit "Nutzer konnte nicht erstellt werden"
sudo mysql -e "GRANT ALL PRIVILEGES ON homeassistant.* TO 'homeassistant'@'localhost';" || error_exit "Berechtigungen konnten nicht gesetzt werden"
sudo mysql -e "FLUSH PRIVILEGES;"

# Home Assistant (lokal)
print_header "7. Home Assistant Installation"
sudo useradd -rm homeassistant -G dialout,gpio,i2c,video || error_exit "Nutzer anlegen fehlgeschlagen"
sudo mkdir /srv/homeassistant || error_exit "Verzeichnis erstellen fehlgeschlagen"
sudo chown homeassistant:homeassistant /srv/homeassistant

sudo -u homeassistant -H -s <<EOF
cd /srv/homeassistant
python3 -m venv .
source bin/activate
pip3 install wheel
pip3 install homeassistant
exit
EOF

# Home Assistant Service mit MariaDB
sudo tee /etc/systemd/system/home-assistant@homeassistant.service > /dev/null <<EOF
[Unit]
Description=Home Assistant
After=network-online.target mariadb.service

[Service]
Type=simple
User=homeassistant
WorkingDirectory=/srv/homeassistant
ExecStart=/srv/homeassistant/bin/hass -c "/home/homeassistant/.homeassistant"
RestartForceExitStatus=100

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable home-assistant@homeassistant
sudo systemctl start home-assistant@homeassistant

# LocalTuya Vorbereitung
print_header "8. LocalTuya Setup"
sudo -u homeassistant -H -s <<EOF
cd /srv/homeassistant
source bin/activate
pip3 install localtuya
exit
EOF

echo -e "${YELLOW}\n[MANUELLER SCHRITT] LocalTuya Konfiguration:"
echo "1. Tuya-Gerät im lokalen Netzwerk ermitteln:"
echo "   sudo apt-get install -y npm && sudo npm install -g tuya-cli"
echo "   tuya-cli list-app"
echo "2. configuration.yaml anpassen (Beispiel folgt im Log)"
echo -e "${NC}"

# MQTT Broker (lokal)
print_header "9. MQTT Broker"
sudo mosquitto_passwd -c /etc/mosquitto/passwd growbox || error_exit "MQTT Nutzer konnte nicht erstellt werden"

sudo tee /etc/mosquitto/conf.d/growbox.conf > /dev/null <<EOF
listener 1883
allow_anonymous false
password_file /etc/mosquitto/passwd
EOF

sudo systemctl restart mosquitto

# Finale Konfiguration
print_header "10. Abschluss"
echo -e "${GREEN}\n=== Installation abgeschlossen! ===${NC}"
echo -e "Kamera:   http://$(hostname -I | awk '{print $1}'):8080"
echo -e "Home Assistant: http://$(hostname -I | awk '{print $1}'):8123"
echo -e "Grafana:  http://$(hostname -I | awk '{print $1}'):3000"
echo -e "MQTT:     Broker auf Port 1883 (Nutzer: growbox)"

echo -e "\n${YELLOW}LocalTuya Beispiel-Konfiguration (in configuration.yaml):${NC}" | tee -a "$LOG_FILE"
cat <<EOF | tee -a "$LOG_FILE"
switch:
  - platform: localtuya
    host: "192.168.1.100"
    local_key: "dein_lokaler_key"
    device_id: "tuya_device_id"
    protocol: "3.3"
    switches:
      steckdose_1:
        name: "Growbox Licht"
        id: 1
      steckdose_2:
        name: "Growbox Lüfter"
        id: 2
EOF

echo -e "\n${BLUE}Nach dem ersten Start von Home Assistant:"
echo "1. LocalTuya Integration manuell hinzufügen"
echo "2. MQTT Integration hinzufügen (Broker: localhost, Port: 1883)"
echo -e "${NC}"

# Neustart
echo -e "${YELLOW}\nNeustart empfohlen. Jetzt neustarten? (j/n)${NC}"
read -r answer
if [[ "$answer" =~ [jJ] ]]; then
    sudo reboot
fi
