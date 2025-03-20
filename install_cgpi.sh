#!/bin/bash

# GrowPi Setup Script - Installiert alle benötigten Pakete und konfiguriert das System

# Logging einrichten
LOG_FILE="/var/log/growpi_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "GrowPi Setup gestartet am $(date)"

# Konfigurationsdatei erstellen
CONFIG_FILE="/etc/growpi/config.ini"
sudo mkdir -p /etc/growpi
echo "[growpi]" | sudo tee $CONFIG_FILE
echo "api_port = 5000" | sudo tee -a $CONFIG_FILE

echo "--- GrowPi Setup startet ---"

# System updaten und vorbereiten
echo "--- System wird aktualisiert ---"
sudo apt update -y && sudo apt upgrade -y || { echo "Fehler beim System-Update"; exit 1; }

# Grafana Repository hinzufügen (wichtig, um Grafana zu finden)
echo "--- Grafana Repository hinzufügen ---"
sudo apt install -y apt-transport-https
sudo mkdir -p /etc/apt/keyrings
curl -sSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update -y

# Wichtige Pakete installieren
echo "--- Installiere grundlegende Pakete ---"
sudo apt install -y git python3 python3-pip python3-venv i2c-tools lm-sensors screen tmux htop curl nginx mosquitto mosquitto-clients influxdb grafana || { echo "Fehler bei der Paketinstallation"; exit 1; }

# I2C, SPI und 1-Wire aktivieren
echo "--- Aktiviere I2C, SPI und 1-Wire ---"
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0
sudo raspi-config nonint do_onewire 0

# Python-Bibliotheken für Sensoren installieren
echo "--- Installiere Python-Bibliotheken für Sensoren ---"
pip3 install RPi.GPIO adafruit-circuitpython-dht adafruit-circuitpython-bme280 adafruit-circuitpython-mcp3008 paho-mqtt flask influxdb-client || { echo "Fehler bei der Python-Bibliotheken-Installation"; exit 1; }

# InfluxDB und Grafana konfigurieren
echo "--- Konfiguriere InfluxDB und Grafana ---"
sudo systemctl enable influxdb grafana-server
sudo systemctl start influxdb grafana-server

# MQTT Broker installieren und starten
echo "--- Installiere und starte Mosquitto MQTT Broker ---"
sudo systemctl enable mosquitto
sudo systemctl start mosquitto

# Home Assistant installieren
echo "--- Installiere Home Assistant ---"
python3 -m venv homeassistant
source homeassistant/bin/activate
pip install homeassistant || { echo "Fehler bei der Home Assistant Installation"; exit 1; }

# Webserver für API aufsetzen
echo "--- Erstelle Flask Webserver für eigene API ---"
cat <<EOF > /home/pi/growpi_api.py
from flask import Flask, jsonify
import random
app = Flask(__name__)

@app.route('/api/data')
def get_data():
    return jsonify({"temperature": random.uniform(18, 25), "humidity": random.uniform(50, 70)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Skript ausführbar machen
chmod +x /home/pi/growpi_api.py

# Systemdienst für API erstellen
echo "--- Erstelle Systemdienst für GrowPi API ---"
cat <<EOF | sudo tee /etc/systemd/system/growpi_api.service
[Unit]
Description=GrowPi API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/growpi_api.py
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable growpi_api.service
sudo systemctl start growpi_api.service

# Backup wichtiger Konfigurationsdateien
echo "--- Erstelle Backup wichtiger Konfigurationsdateien ---"
BACKUP_DIR="/home/pi/growpi_backup"
mkdir -p $BACKUP_DIR
cp /etc/mosquitto/mosquitto.conf $BACKUP_DIR/
cp /etc/influxdb/influxdb.conf $BACKUP_DIR/

# Überprüfung der Installationen
echo "--- Überprüfe Dienste ---"
systemctl is-active --quiet influxdb && echo "InfluxDB läuft" || echo "Fehler: InfluxDB läuft nicht"
systemctl is-active --quiet grafana-server && echo "Grafana läuft" || echo "Fehler: Grafana läuft nicht"
systemctl is-active --quiet mosquitto && echo "Mosquitto läuft" || echo "Fehler: Mosquitto läuft nicht"
systemctl is-active --quiet growpi_api && echo "GrowPi API läuft" || echo "Fehler: GrowPi API läuft nicht"

# Sicherheitshinweis
echo "--- Sicherheitshinweis ---"
echo "Bitte ändern Sie das Standard-Passwort für den Pi-Benutzer mit dem Befehl 'passwd'"

echo "--- Installation abgeschlossen! ---"
echo "Ein Neustart wird empfohlen. Möchten Sie jetzt neustarten? (j/n)"
read answer
if [ "$answer" = "j" ]; then
    sudo reboot
else
    echo "Bitte denken Sie daran, das System später neu zu starten."
fi
