#!/bin/bash

# Growboto Setup Script - Installiert alle benötigten Pakete und konfiguriert das System

# ASCII-Logo anzeigen
echo """
                                             /$$                   /$$              
                                            | $$                  | $$              
  /$$$$$$   /$$$$$$   /$$$$$$  /$$  /$$  /$$| $$$$$$$   /$$$$$$  /$$$$$$    /$$$$$$ 
 /$$__  $$ /$$__  $$ /$$__  $$| $$ | $$ | $$| $$__  $$ /$$__  $$|_  $$_/   /$$__  $$
| $$  \ $$| $$  \__/| $$  \ $$| $$ | $$ | $$| $$  \ $$| $$  \ $$  | $$    | $$  \ $$
| $$  | $$| $$      | $$  | $$| $$ | $$ | $$| $$  | $$| $$  | $$  | $$ /$$| $$  | $$
|  $$$$$$$| $$      |  $$$$$$/|  $$$$$/$$$$/| $$$$$$$/|  $$$$$$/  |  $$$$/|  $$$$$$/
 \____  $$|__/       \______/  \_____/\___/ |_______/  \______/    \___/   \______/ 
 /$$  \ $$                                                                          
|  $$$$$$/                                                                          
 \______/                                                                           


 🪴🤖 G R O W B O T O 1.0 -  AI automatisiertes Grow-System 🤖🪴
"""

# Logging einrichten
LOG_FILE="/var/log/growboto_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Growboto Setup gestartet am $(date)"

# Konfigurationsdatei erstellen
CONFIG_FILE="/etc/growboto/config.ini"
sudo mkdir -p /etc/growboto
echo "[growboto]" | sudo tee $CONFIG_FILE
echo "api_port = 5000" | sudo tee -a $CONFIG_FILE

echo "--- Growboto Setup startet ---"

# System updaten und vorbereiten
echo "--- System wird aktualisiert ---"
sudo apt update && sudo apt upgrade -y

# Wichtige Pakete installieren
echo "--- Installiere grundlegende Pakete ---"
sudo apt install -y git python3 python3-pip python3-venv i2c-tools lm-sensors screen tmux htop curl nginx mosquitto mosquitto-clients influxdb grafana

# I2C, SPI und 1-Wire aktivieren
echo "--- Aktiviere I2C, SPI und 1-Wire ---"
sudo raspi-config nonint do_i2c 0
sudo raspi-config nonint do_spi 0
sudo raspi-config nonint do_onewire 0

# Python-Bibliotheken für Sensoren installieren
echo "--- Installiere Python-Bibliotheken für Sensoren ---"
pip3 install RPi.GPIO adafruit-circuitpython-dht adafruit-circuitpython-bme280 adafruit-circuitpython-mcp3008

# Prometheus und Grafana für Monitoring installieren
echo "--- Installiere Prometheus und Grafana ---"
sudo systemctl enable influxdb grafana-server
sudo systemctl start influxdb grafana-server

# MQTT Broker (Mosquitto) installieren
echo "--- Installiere Mosquitto MQTT Broker ---"
sudo systemctl enable mosquitto
sudo systemctl start mosquitto

# Webserver für API aufsetzen
echo "--- Erstelle Flask Webserver für Growboto API ---"
cat <<EOF > /home/pi/growboto_api.py
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
chmod +x /home/pi/growboto_api.py

# Systemdienst für API erstellen
echo "--- Erstelle Systemdienst für Growboto API ---"
cat <<EOF | sudo tee /etc/systemd/system/growboto_api.service
[Unit]
Description=Growboto API
After=network.target

[Service]
ExecStart=/usr/bin/python3 /home/pi/growboto_api.py
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable growboto_api.service
sudo systemctl start growboto_api.service

echo "--- Installation abgeschlossen! Neustart in 5 Sekunden... ---"
sleep 5
sudo reboot
