import Adafruit_DHT
import time

# Sensor-Typ und GPIO-Pin festlegen
sensor = Adafruit_DHT.AM2302  # AM2301 wird oft als AM2302 erkannt
pin = 4  # GPIO4 (Pin 7)

try:
    while True:
        humidity, temperature = Adafruit_DHT.read_retry(sensor, pin)
        if humidity is not None and temperature is not None:
            print(f"Temp: {temperature:.1f}°C, Luftfeuchtigkeit: {humidity:.1f}%")
        else:
            print("Fehler beim Auslesen!")
        time.sleep(2)
except KeyboardInterrupt:
    print("Programm beendet")
