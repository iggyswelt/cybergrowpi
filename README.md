Hier ist das **komplette GitHub README.md** für dein CyberGrowPi-Projekt, kombiniert mit den besten Teilen unserer Scripts:

```markdown
# 🌿 CyberGrowPi - Automatisierte Growbox mit Raspberry Pi

[![GitHub license](https://img.shields.io/github/license/iggyswelt/CyberGrowPi)](https://github.com/iggyswelt/CyberGrowPi/blob/main/LICENSE)
[![YouTube Channel](https://img.shields.io/badge/YouTube-@iggyswelt-red)](https://www.youtube.com/@iggyswelt)

![CyberGrowPi Banner](https://via.placeholder.com/800x200.png?text=CyberGrowPi+-+Automated+Growbox+System)

> **DIY Open-Source Projekt** für eine kostengünstige, automatisierte Growbox – perfekt für Pflanzen wie Hanf und Tomaten!

## 🚀 Was das Script alles kann

### 🌟 Kernfunktionen
| Feature               | Beschreibung                                                                 |
|-----------------------|-----------------------------------------------------------------------------|
| **Plug & Play Setup** | Vollautomatische Installation mit einem Befehl                              |
| **Smart Control**     | Home Assistant für Automatisierung (Licht, Lüfter, Heizung)                |
| **Echtzeit-Monitoring** | Grafana Dashboard mit Sensordaten (Temperatur, Feuchtigkeit, etc.)        |
| **4K-Kamera-Stream**  | mjpg-streamer mit Tag/Nacht-Modus                                           |
| **100% Lokal**        | Keine Cloud-Abhängigkeit – alles läuft auf deinem Raspberry Pi             |

### 🔧 Technische Highlights
```bash
✅ Automatische Fehlerkorrektur bei Paketkonflikten
✅ Optimiert für Raspberry Pi (geringer Ressourcenverbrauch)
✅ Integrierte WLAN-Steckdosensteuerung (Tuya/Home Assistant)
✅ Professionelles Logging & Systemüberwachung
```

## 🛠️ Hardware-Setup
### 📋 Sensoren
| Sensor          | Position                | Messwerte                     |
|-----------------|-------------------------|-------------------------------|
| BME680          | Oben in der Box         | Luftqualität, Temp, Feuchtigkeit |
| DS18B20         | 3x Topferde, 1x Wassertank | Bodentemperatur              |
| AM2301/DHT21    | Keller & Box-Boden      | Raumklima                     |
| Bodenfeuchte    | In den Töpfen           | Substrat-Feuchtigkeit         |

### 💡 Aktoren
- **200W LED-Licht** (Hauptbeleuchtung)
- **27/38W Abluftventilator**
- **20W Umluftventilator**
- **1000W Heizlüfter** (für kalte Keller)

## ⚡ Schnellstart
### Installation
```bash
wget https://raw.githubusercontent.com/iggyswelt/CyberGrowPi/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

### 🔍 Wichtige URLs nach Installation
| Dienst           | URL                               |
|------------------|-----------------------------------|
| Home Assistant   | `http://<deine-ip>:8123`         |
| Grafana          | `http://<deine-ip>:3000`         |
| Kamera-Stream    | `http://<deine-ip>:8080/stream`  |

## 🛠️ Wartungsbefehle
```bash
# Systemstatus prüfen
sudo systemctl status growcam.service home-assistant@homeassistant

# Logs anzeigen
journalctl -u home-assistant@homeassistant -f  # Live-Logs
tail -f /var/log/growbox_control.log          # Kontrollscript

# Kamera testen
curl http://localhost:8080/?action=snapshot -o test.jpg
```

## 🌡️ Optimale Bedingungen
| Parameter        | Wachstumsphase | Blütephase |
|------------------|---------------|------------|
| Temperatur       | 22–28°C       | 20–26°C    |
| Luftfeuchtigkeit | 50–70%        | 40–50%     |
| Bodentemp.       | 20–24°C       | 18–22°C    |

> 💡 **Tipp für kalte Keller:** Heizlüfter mit Hysterese steuern (ein bei 20°C, aus bei 22°C)

## 🤝 Mitmachen
Wir freuen uns über Beiträge!  
🔹 Issues für Problemberichte  
🔹 Pull Requests für Verbesserungen  
🔹 YouTube-Kanal: [@iggyswelt](https://www.youtube.com/@iggyswelt)
🔹 YouTube CyberGrowbox Playlist: https://www.youtube.com/playlist?list=PL2DuNzwDyBSKBzJjWaHxaxo5vNI4Zr9vu

## 📜 Lizenz
MIT License - Kommerzielle Nutzung erlaubt, Quellangabe erwünscht

---

> **"Die beste Growbox entsteht, wenn man die Technik vergisst und sich auf die Pflanzen konzentrieren kann."** 🌱✨
```

### 🎨 Empfohlene Ergänzungen:
1. **Screenshots**:
   - Füge echte Bilder deiner Growbox hinzu
   - Beispiel-Dashboards (Grafana/Home Assistant)

2. **Videos**:
   ```markdown
   ## 🎥 Demo-Video
   [![Video-Tutorial](https://img.youtube.com/vi/DEINVIDEOID/0.jpg)](https://youtu.be/DEINVIDEOID)
   ```

3. **Hardware-Fotos**:
   ```markdown
   ## 📸 Build-Anleitung
   ![Verdrahtung](photos/wiring.jpg) 
   ![Sensorplatzierung](photos/sensors.jpg)
   ```

4. **Sponsoring-Info** (falls gewünscht):
   ```markdown
   ## ☕ Unterstützung
   Gefällt dir das Projekt? [Buy me a coffee!](https://ko-fi.com/iggyswelt)
   ```
