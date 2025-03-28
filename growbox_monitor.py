#!/usr/bin/env python3
"""
growbox_monitor.py - Kombiniertes System- und Sensor-Monitoring
Autor: Iggy
Version: 1.1
"""

import os
import sys
import time
import subprocess
import logging
from datetime import datetime

# Logging Setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/growbox_monitor.log"),
        logging.StreamHandler()
    ]
)

# Farben für Terminalausgabe
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'

# Virtuelle Umgebung und Abhängigkeiten
VENV_DIR = os.path.expanduser("~/growbox_venv")
REQUIREMENTS = [
    'Adafruit-DHT',
    'bme680',
    'RPi.GPIO',
    'requests'
]

def setup_venv():
    """Erstellt virtuelle Umgebung und installiert Abhängigkeiten"""
    if not os.path.exists(VENV_DIR):
        logging.info(f"{Colors.BLUE}Erstelle virtuelle Umgebung in {VENV_DIR}{Colors.END}")
        subprocess.run([sys.executable, "-m", "venv", VENV_DIR], check=True)
        
        pip_path = os.path.join(VENV_DIR, "bin", "pip")
        logging.info(f"{Colors.BLUE}Installiere Python-Pakete...{Colors.END}")
        for package in REQUIREMENTS:
            subprocess.run([pip_path, "install", package], check=True)

def check_system_services():
    """Überprüft Systemdienste"""
    services = [
        "growcam.service",
        "home-assistant@homeassistant",
        "mosquitto",
        "grafana-server",
        "influxdb"
    ]
    
    logging.info(f"\n{Colors.BLUE}=== Systemdienst-Check ==={Colors.END}")
    for service in services:
        result = subprocess.run(
            ["systemctl", "is-active", service],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            logging.info(f"{Colors.GREEN}[OK]{Colors.END} {service} ist aktiv")
        else:
            logging.error(f"{Colors.RED}[FEHLER]{Colors.END} {service} ist inaktiv")
            subprocess.run(["sudo", "systemctl", "restart", service])

def check_disk_space():
    """Überprüft Festplattenplatz"""
    result = subprocess.run(
        ["df", "-h", "/"],
        capture_output=True,
        text=True
    )
    usage = int(result.stdout.split("\n")[1].split()[4].replace("%", ""))
    if usage > 90:
        logging.warning(f"{Colors.RED}[KRITISCH]{Colors.END} Festplattenauslastung: {usage}%")
    elif usage > 80:
        logging.warning(f"{Colors.YELLOW}[WARNUNG]{Colors.END} Festplattenauslastung: {usage}%")
    else:
        logging.info(f"{Colors.GREEN}[OK]{Colors.END} Festplattenauslastung: {usage}%")

def check_sensors():
    """Testet alle angeschlossenen Sensoren"""
    logging.info(f"\n{Colors.BLUE}=== Sensor-Check ==={Colors.END}")
    
    # BME680 Test
    try:
        import bme680
        sensor = bme680.BME680()
        if sensor.get_sensor_data():
            logging.info(f"{Colors.GREEN}[OK]{Colors.END} BME680 - Temp: {sensor.data.temperature:.1f}°C")
        else:
            logging.error(f"{Colors.RED}[FEHLER]{Colors.END} BME680 antwortet nicht")
    except Exception as e:
        logging.error(f"{Colors.RED}[FEHLER]{Colors.END} BME680: {str(e)}")

    # AM2301 Test
    try:
        import Adafruit_DHT
        humidity, temp = Adafruit_DHT.read_retry(Adafruit_DHT.AM2302, 4)
        if humidity is not None and temp is not None:
            logging.info(f"{Colors.GREEN}[OK]{Colors.END} AM2301 - Temp: {temp:.1f}°C, Feuchtigkeit: {humidity:.1f}%")
        else:
            logging.error(f"{Colors.RED}[FEHLER]{Colors.END} AM2301 liefert keine Daten")
    except Exception as e:
        logging.error(f"{Colors.RED}[FEHLER]{Colors.END} AM2301: {str(e)}")

    # DS18B20 Test
    try:
        base_dir = "/sys/bus/w1/devices/"
        devices = [d for d in os.listdir(base_dir) if d.startswith("28-")]
        if not devices:
            logging.error(f"{Colors.RED}[FEHLER]{Colors.END} Keine DS18B20 Sensoren gefunden")
        else:
            for device in devices:
                device_file = os.path.join(base_dir, device, "temperature")
                if os.path.exists(device_file):
                    with open(device_file, "r") as f:
                        temp = float(f.read()) / 1000.0
                    logging.info(f"{Colors.GREEN}[OK]{Colors.END} DS18B20 ({device}): {temp:.1f}°C")
                else:
                    logging.error(f"{Colors.RED}[FEHLER]{Colors.END} DS18B20 {device} defekt")
    except Exception as e:
        logging.error(f"{Colors.RED}[FEHLER]{Colors.END} DS18B20: {str(e)}")

def main():
    setup_venv()
    
    # Python-Pfad der virtuellen Umgebung verwenden
    python_path = os.path.join(VENV_DIR, "bin", "python")
    if not os.path.exists(python_path):
        logging.error("Virtuelle Umgebung konnte nicht erstellt werden!")
        sys.exit(1)
    
    logging.info(f"\n{Colors.BLUE}=== Growbox Monitor Start ==={Colors.END}")
    check_system_services()
    check_disk_space()
    check_sensors()
    logging.info(f"{Colors.BLUE}=== Prüfung abgeschlossen ==={Colors.END}")

if __name__ == "__main__":
    main()
