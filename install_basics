# install cybergrowpi basics
#!/bin/bash

# GrowPi Setup Script - Installiert alle benötigten Pakete und konfiguriert das System

echo "--- GrowPi Setup startet ---"

# System updaten
echo "--- System wird aktualisiert ---"
sudo apt update && sudo apt upgrade -y

# Wichtige Pakete installieren
echo "--- Installiere grundlegende Pakete ---"
sudo apt install -y git python3 python3-pip python3-venv i2c-tools lm-sensors screen tmux htop curl

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
sudo apt install -y prometheus grafana
sudo systemctl enable prometheus grafana-server
sudo systemctl start prometheus grafana-server

# MQTT Broker (Mosquitto) installieren
echo "--- Installiere Mosquitto MQTT Broker ---"
sudo apt install -y mosquitto mosquitto-clients
sudo systemctl enable mosquitto
sudo systemctl start mosquitto

# Benutzerfreundliche Tools installieren
echo "--- Installiere Webserver & Remote-Tools ---"
sudo apt install -y nginx xrdp realvnc-vnc-server
sudo systemctl enable xrdp
sudo systemctl enable vncserver-x11-serviced

# Neustart nach Installation
echo "--- Installation abgeschlossen! Neustart in 5 Sekunden... ---"
sleep 5
sudo reboot
