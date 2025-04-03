#!/usr/bin/env python3
import bme680
import paho.mqtt.client as mqtt
import time

# --- Konfiguration ---
MQTT_BROKER = "localhost"  # Assuming Mosquitto is running on the Raspberry Pi
MQTT_TOPIC = "growbox/sensors/bme680"
SENSOR_ADDRESS = 0x76  # Default I2C address, check with 'i2cdetect -y 1'

try:
    sensor = bme680.BME680(i2c_addr=SENSOR_ADDRESS)
except IOError:
    print("Error: BME680 sensor not found at address 0x{:02x}. Check your wiring and I2C configuration.")
    exit(1)

# --- Sensor Configuration (Optional but Recommended) ---
sensor.set_humidity_oversample(bme680.OS_2X)
sensor.set_pressure_oversample(bme680.OS_4X)
sensor.set_temperature_oversample(bme680.OS_8X)
sensor.set_filter(bme680.FILTER_SIZE_3)
sensor.set_gas_heater_temperature(320)
sensor.set_gas_heater_duration(150)
sensor.select_gas_heater_profile(0)

client = mqtt.Client()

try:
    client.connect(MQTT_BROKER)
except Exception as e:
    print(f"Error connecting to MQTT broker: {e}")
    exit(1)

try:
    while True:
        if sensor.get_sensor_data():
            output = {
                "temperature": sensor.data.temperature,
                "humidity": sensor.data.humidity,
                "pressure": sensor.data.pressure,
            }
            if sensor.data.heat_stable:
                output["gas_resistance"] = sensor.data.gas_resistance

            client.publish(MQTT_TOPIC, payload=str(output), qos=0, retain=True)
            print(f"Published data: {output} to topic: {MQTT_TOPIC}")

        time.sleep(5)  # Adjust as needed
except KeyboardInterrupt:
    print("Exiting sensor script.")
finally:
    client.disconnect()
