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

echo "=== Growbox AI Setup ==="
echo "OS Version: $(lsb_release -sd)"
echo "========================="

# 1) Systemvorbereitung
echo -e "\n\033[1;32m[1/6] Systemaktualisierung\033[0m"
sudo apt update -y
sudo apt full-upgrade -y --auto-remove

# 2) Abhängigkeiten mit korrigiertem jpeg-dev Paket
echo -e "\n\033[1;32m[2/6] Paketinstallation\033[0m"
sudo apt install -y \
    git python3-venv python3-dev \
    libjpeg62-turbo-dev libopenjp2-7 libtiff5-dev \
    cmake libv4l-dev v4l-utils \
    i2c-tools lm-sensors || { echo "Paketinstallation fehlgeschlagen"; exit 1; }

# 3) Kamera-Setup
echo -e "\n\033[1;32m[3/6] Kamera-Konfiguration\033[0m"
sudo raspi-config nonint do_camera 0
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0

# 4) MJPG-Streamer Installation mit verbesserter Fehlerbehandlung
echo -e "\n\033[1;32m[4/6] Kamera-Stream Installation\033[0m"
MJPG_DIR="$HOME/mjpg-streamer"
rm -rf "$MJPG_DIR"  # Vorherige Installation entfernen

# Fehlerbehandlung für git clone
if ! git clone https://github.com/jacksonliam/mjpg-streamer.git "$MJPG_DIR"; then
    echo "Fehler beim Klonen des Repositories. Überprüfe die Internetverbindung und versuche es erneut."
    exit 1
fi

cd "$MJPG_DIR/mjpg-streamer-experimental" || { echo "Fehler beim Wechseln in das Verzeichnis"; exit 1; }

# Kompilierungsfehler prüfen
if ! make CMAKE_BUILD_TYPE=Release; then
    echo "Fehler beim Kompilieren. Überprüfe Abhängigkeiten oder versuche es später erneut."
    exit 1
fi

if ! sudo make install; then
    echo "Fehler bei der Installation von MJPG-Streamer."
    exit 1
fi

# 5) Systemd-Service mit automatischer Geräteerkennung
echo -e "\n\033[1;32m[5/6] Autostart-Konfiguration\033[0m"
sudo tee /etc/systemd/system/growcam.service << EOF
[Unit]
Description=Growbox Camera Stream
After=network.target

[Service]
User=$USER
ExecStart=/usr/local/bin/mjpg_streamer \
  -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 15" \
  -o "output_http.so -w /usr/local/share/mjpg-streamer/www"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Systemd-Service neu laden und aktivieren
sudo systemctl daemon-reload
sudo systemctl enable growcam.service

# 6) Finale Überprüfung
echo -e "\n\033[1;32m[6/6] Systemprüfung\033[0m"
echo "Erkannte Kameras:"
v4l2-ctl --list-devices | grep -A2 "UVC Camera"

echo -e "\n\033[1;34mInstallation abgeschlossen!\033[0m"
echo "Stream-URL: http://$(hostname -I | cut -d' ' -f1):8080/?action=stream"
echo "Steuerung: sudo systemctl [start|stop|status] growcam.service"

# Zusätzliche Informationen
echo -e "\n\033[1;33mWichtige Hinweise:\033[0m"
echo "1. Starten Sie den Stream mit: sudo systemctl start growcam.service"
echo "2. Überprüfen Sie den Status mit: sudo systemctl status growcam.service"
echo "3. Bei Problemen, prüfen Sie die Logs mit: journalctl -u growcam.service"
echo "4. Kamera-Einstellungen können mit v4l2-ctl angepasst werden
