#!/bin/bash
# Growboto Setup Script - Installiert alle benötigten Pakete und konfiguriert das System
# ASCII-Logo anzeigen
cat << 'EOF'
                                             /$$                                           /$$
                                            | $$                                          |__/
  /$$$$$$   /$$$$$$   /$$$$$$  /$$  /$$  /$$| $$$$$$$   /$$$$$$  /$$   /$$        /$$$$$$  /$$
 /$$__  $$ /$$__  $$ /$$__  $$| $$ | $$ | $$| $$__  $$ /$$__  $$|  $$ /$$/       /$$__  $$| $$
| $$  \ $$| $$  \__/| $$  \ $$| $$ | $$ | $$| $$  \ $$| $$  \ $$ \  $$$$/       | $$  \ $$| $$
| $$  | $$| $$      | $$  | $$| $$ | $$ | $$| $$  | $$| $$  | $$  >$$  $$       | $$  | $$| $$
|  $$$$$$$| $$      |  $$$$$$/|  $$$$$/$$$$/| $$$$$$$/|  $$$$$$/ /$$/\  $$      | $$$$$$$/| $$
 \____  $$|__/       \______/  \_____/\___/ |_______/  \______/ |__/  \__/      | $$____/ |__/
 /$$  \ $$                                                                      | $$          
|  $$$$$$/                                                                      | $$          
 \______/                                                                       |__/          

 G R O W B O T O  -  Automatisiertes Grow-System 🚀
EOF
# Growbox Pi Setup Script - Idiotensicher & Getestet
# Version 3.0 - 2025-03-27
# Autor: Iggy & deepseek
# youtube: https://www.youtube.com/@iggyswelt
# GitHub:  https://github.com/iggyswelt/cybergrowpi

# Farben für nicen output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log-Datei
LOG_FILE="/var/log/growbox_setup.log"
sudo touch "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Funktionen
error_exit() {
    echo -e "${RED}[FEHLER] $1${NC}" >&2
    echo -e "${YELLOW}Details im Log: $LOG_FILE${NC}"
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

# Header
echo -e "\n${GREEN}=== Growbox Pi Setup Script ==="
echo "=== Version 3.0 ==="
echo "=== Start: $(date) ==="
echo "=== Log: $LOG_FILE ===${NC}"

# 1. Systemupdate
print_header "1/6 | Systemaktualisierung"
sudo apt-get update -y || error_exit "Update fehlgeschlagen!"
sudo apt-get upgrade -y || error_exit "Upgrade fehlgeschlagen!"
sudo apt-get autoremove -y

# 2. Pakete installieren
print_header "2/6 | Installiere Pakete"
REQUIRED_PACKAGES=(
    git python3 python3-pip python3-venv
    i2c-tools lm-sensors v4l-utils
    nginx mosquitto mosquitto-clients
    influxdb grafana fswebcam
    libjpeg62-turbo-dev libv4l-dev cmake
    ffmpeg motion
)

# Grafana Repo hinzufügen
curl -fsSL https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

sudo apt-get update || error_exit "Repository-Update fehlgeschlagen"
sudo apt-get install -y "${REQUIRED_PACKAGES[@]}" || error_exit "Paketinstallation fehlgeschlagen"

# 3. Hardware aktivieren
print_header "3/6 | Aktiviere Schnittstellen"
sudo raspi-config nonint do_camera 0 || error_exit "Kamera konnte nicht aktiviert werden"
sudo raspi-config nonint do_i2c 0 || error_exit "I2C konnte nicht aktiviert werden"
sudo raspi-config nonint do_spi 0 || error_exit "SPI konnte nicht aktiviert werden"
sudo raspi-config nonint do_onewire 0 || error_exit "1-Wire konnte nicht aktiviert werden"

# 4. mjpg-streamer installieren
print_header "4/6 | Installiere mjpg-streamer"
if [ ! -f "/usr/local/bin/mjpg_streamer" ]; then
    echo "Installiere mjpg-streamer von Source..."
    MJPG_DIR="/opt/mjpg-streamer"
    sudo mkdir -p "$MJPG_DIR"
    sudo chown "$USER":"$USER" "$MJPG_DIR"
    
    cd "$MJPG_DIR" || error_exit "Kann nicht nach $MJPG_DIR wechseln"
    git clone https://github.com/jacksonliam/mjpg-streamer.git || error_exit "Klonen fehlgeschlagen"
    
    cd mjpg-streamer/mjpg-streamer-experimental || error_exit "Verzeichnis nicht gefunden"
    make clean && make || error_exit "Kompilierung fehlgeschlagen"
    sudo make install || error_exit "Installation fehlgeschlagen"
    
    # Symlink für einfachen Zugriff
    sudo ln -sf "$MJPG_DIR/mjpg-streamer-experimental/mjpg_streamer" /usr/local/bin/
    
    # Web-Verzeichnis erstellen
    sudo mkdir -p /usr/local/www
    sudo chown -R "$USER":"$USER" /usr/local/www
else
    echo "mjpg-streamer ist bereits installiert."
fi

# 5. Kamera konfigurieren
print_header "5/6 | Kamera-Setup"
sudo usermod -aG video "$USER" || echo -e "${YELLOW}Warnung: Nutzer bereits in Video-Gruppe${NC}"
sudo chmod 666 /dev/video0 || echo -e "${YELLOW}Warnung: Berechtigungen für /dev/video0 konnten nicht gesetzt werden${NC}"

# Unterstützte Formate anzeigen
echo -e "\n${YELLOW}Verfügbare Kameraformate:${NC}"
v4l2-ctl --device=/dev/video0 --list-formats-ext || error_exit "Kamera nicht erreichbar"

# 6. Systemd-Service erstellen
print_header "6/6 | Autostart einrichten"
SERVICE_FILE="/etc/systemd/system/growcam.service"

# Optimierte Konfiguration basierend auf unseren Tests
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
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

# Service aktivieren
sudo systemctl daemon-reload || error_exit "Daemon-Reload fehlgeschlagen"
sudo systemctl enable growcam.service || error_exit "Service-Aktivierung fehlgeschlagen"
sudo systemctl start growcam.service || error_exit "Service-Start fehlgeschlagen"

# Finale Überprüfung
sleep 2
echo -e "\n${YELLOW}Service-Status:${NC}"
systemctl status growcam.service --no-pager || error_exit "Service läuft nicht!"

# Zusammenfassung
echo -e "\n${GREEN}=== Installation abgeschlossen! ===${NC}"
echo -e "Kamera-Stream: ${BLUE}http://$(hostname -I | awk '{print $1}'):8080/?action=stream${NC}"
echo -e "Snapshot:      ${BLUE}http://$(hostname -I | awk '{print $1}'):8080/?action=snapshot${NC}"
echo -e "Grafana:       ${BLUE}http://$(hostname -I | awk '{print $1}'):3000${NC}"
echo -e "\n${YELLOW}Tipp: Nutze 'journalctl -u growcam.service -f' für Debugging${NC}"

# Neustart empfehlen
echo -e "\n${YELLOW}Ein Neustart wird empfohlen. Jetzt neustarten? (j/n)${NC}"
read -r answer
if [[ "$answer" =~ [jJ] ]]; then
    sudo reboot
else
    echo -e "${YELLOW}Vergiss nicht, später neu zu starten!${NC}"
fi
