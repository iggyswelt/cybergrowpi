# CyberGrowPi - DIY Open-Source Growbox Projekt

Willkommen bei **CyberGrowPi**, einem DIY Open-Source Bastelprojekt des YouTube-Kanals **@iggyswelt** https://www.youtube.com/@iggyswelt ! Dieses Projekt zeigt, wie du eine kostengünstige, automatisierte Growbox mit einem Raspberry Pi, verschiedenen Sensoren und einer WLAN-Steckdosenleiste baust. Ziel ist es, die Umweltbedingungen für Pflanzen wie Hanf und Tomaten zu optimieren, ohne teure kommerzielle Systeme wie AC Infinity oder Spider Farmer zu kaufen. Alle Details, Schaltpläne und der Code werden hier auf GitHub open-source bereitgestellt, damit du dein eigenes System nachbauen kannst.

nützliche Befehle:
# System-Status
sudo systemctl status growcam.service home-assistant@homeassistant

# Logs anzeigen
journalctl -u home-assistant@homeassistant -f  # HA-Logs live
tail -f /var/log/growbox_control.log          # Kontroll-Script

# Kamera testen
curl http://die-ri-IPAdresse:8080/?action=snapshot -o test.jpg && eog test.jpg

## Projektübersicht

CyberGrowPi ist ein automatisiertes Überwachungs- und Steuerungssystem für eine Growbox mit den Maßen 100x100x180 cm. Die Box steht in einem Keller, der im Winter/Frühjahr Temperaturen zwischen 12–17 °C und eine Luftfeuchtigkeit von 30 % hat. Das System nutzt einen Raspberry Pi, um Temperatur, Luftfeuchtigkeit, Bodenfeuchtigkeit und Luftqualität zu messen und Geräte wie Beleuchtung, Belüftung und Heizung zu steuern.

### Hardware-Setup

#### Sensoren
1. **BME680 (Luftqualität, Temperatur, Luftfeuchtigkeit, Druck, VOCs)**  
   - **Position**: Oben in der Growbox.  
   - **Funktion**: Misst Temperatur, Luftfeuchtigkeit, Luftdruck und flüchtige organische Verbindungen (VOCs), um die Luftqualität zu überwachen. Nützlich, um Schimmelbildung oder schlechte Belüftung zu erkennen.

2. **DS18B20 (Temperatur)**  
   - **Positionen**:  
     - 3x Topferde (DS Sensor 1-3): Bodentemperatur in den Töpfen.  
     - 1x Wassertank (DS Sensor 4): Wassertemperatur.  
     - 1x Stecklingshaus (DS Sensor 5): Temperatur im Stecklingsbereich.  
   - **Funktion**: Präziser digitaler Temperatursensor (1-Wire), ideal für Boden- und Wassertemperaturmessungen.

3. **AM2301 (DHT21) oder BME280 (Backup für Temperatur und Luftfeuchtigkeit)**  
   - **Positionen**:  
     - AM Sensor 1: Keller (Raumtemperatur und Luftfeuchtigkeit).  
     - AM Sensor 2: Growbox Boden (Luftfeuchtigkeit).  
   - **Funktion**: Zuverlässiger Sensor für Temperatur und Luftfeuchtigkeit, dient als Backup oder für zusätzliche Messpunkte. Der BME280 misst zusätzlich Luftdruck (optional).

4. **Bodenfeuchtigkeitssensoren (3x)**  
   - **Position**: In den Töpfen, um die Feuchtigkeit des Substrats zu messen.  
   - **Funktion**: Hilft, die Bewässerung zu optimieren und Staunässe oder Trockenheit zu vermeiden.

#### WLAN-Steckdosenleiste
Die folgenden Geräte werden über eine WLAN-Steckdosenleiste gesteuert:  
1. **200 W Hauptlicht**: LED-Beleuchtung für die Pflanzen.  
2. **27/38 W Abluft**: Abluftventilator für Luftaustausch.  
3. **20 W Umluft**: Umluftventilator für bessere Luftzirkulation.  
4. **1000 W Heizlüfter**: Heizung zur Temperaturregulierung, besonders wichtig im kühlen Keller (12–17 °C).

#### Raspberry Pi
Der Raspberry Pi ist das Herzstück des Systems. Er liest die Sensordaten aus, steuert die Geräte über die WLAN-Steckdosenleiste und speichert die Daten für Analyse und Visualisierung.

---

## Analyse und Optimierungsvorschläge

### 1. Sensoren und Platzierung
Die Sensoren decken alle wichtigen Parameter ab: Temperatur, Luftfeuchtigkeit, Bodenfeuchtigkeit und Luftqualität. Hier sind einige Optimierungstipps:

#### BME680 (Luftqualität oben in der Growbox)
- **Hintergrund**: Der BME680 misst Temperatur, Luftfeuchtigkeit, Druck und VOCs, um die Luftqualität zu überwachen. VOCs können auf Schimmel, CO₂-Anreicherung oder schlechte Belüftung hinweisen.
- **Tipp**: Platziere den Sensor in der Nähe der Pflanzenkronen, aber nicht direkt im Luftstrom des Abluftventilators oder unter dem Hauptlicht, da Hitze und Luftstrom die Messungen verfälschen können.
- **Kalibrierung**: Der BME680 benötigt eine Einbrennzeit von 24–48 Stunden, um genaue VOC-Messungen zu liefern. Lass ihn vor dem Einsatz laufen.
- **Herausforderung im Keller**: Mit einer Luftfeuchtigkeit von 30 % im Keller ist die Luft sehr trocken. In der Growbox solltest du die Luftfeuchtigkeit erhöhen (siehe optimale Werte unten), z. B. durch einen Luftbefeuchter, falls nötig.

#### DS18B20 (Temperatur)
- **Hintergrund**: Der DS18B20 ist ein präziser, digitaler Temperatursensor, der über das 1-Wire-Protokoll mehrere Sensoren in Reihe schalten kann.
- **Tipp für Topferde**: Stecke die Sensoren 5–10 cm tief in das Substrat, nicht zu nah am Topfrand, da die Umgebungsluft die Messungen beeinflussen kann.
- **Wassertank**: Verwende die wasserdichte Version des DS18B20 und achte auf eine gute Abdichtung des Kabels, um Korrosion zu vermeiden.
- **Stecklingshaus**: Stecklinge brauchen 22–25 °C. Platziere den Sensor in der Nähe der Wurzelzone, aber nicht direkt an einer Heizmatte (falls vorhanden).
- **Herausforderung im Keller**: Bei 12–17 °C im Keller wird die Bodentemperatur in den Töpfen wahrscheinlich zu niedrig sein (idealerweise 20–24 °C). Der Heizlüfter muss hier gezielt eingreifen.

#### AM2301/BME280 (Temperatur und Luftfeuchtigkeit)
- **Hintergrund**: Der AM2301 ist ein zuverlässiger Sensor für Temperatur und Luftfeuchtigkeit. Der BME280 ist eine Alternative mit zusätzlicher Luftdruckmessung.
- **Tipp für Growbox Boden (AM Sensor 2)**: Schütze den Sensor vor Spritzwasser (z. B. mit einem perforierten Gehäuse), da er am Boden der Box platziert ist.
- **Keller (AM Sensor 1)**: Die Luftfeuchtigkeit von 30 % im Keller ist sehr niedrig. In der Growbox solltest du die Luftfeuchtigkeit erhöhen, um die optimalen Werte zu erreichen (siehe unten).

#### Bodenfeuchtigkeitssensoren
- **Hintergrund**: Bodenfeuchtigkeitssensoren helfen, die Bewässerung zu optimieren.
- **Tipp**: Verwende kapazitive Sensoren, da resistive Sensoren mit der Zeit korrodieren. Kalibriere die Sensoren, indem du sie in trockenes und dann in gesättigtes Substrat steckst, um Minimum- und Maximumwerte zu bestimmen.
- **Empfehlung**: Halte die Bodenfeuchtigkeit bei 40–60 %, um Staunässe zu vermeiden, besonders in einem kühlen Keller, wo die Verdunstung langsamer ist.

### 2. WLAN-Steckdosenleiste und Geräte
Die Geräte decken Beleuchtung, Belüftung und Temperaturkontrolle ab. Hier einige Optimierungsvorschläge:

#### 200 W Hauptlicht
- **Hintergrund**: 200 W LED-Licht ist für eine 100x100x180 cm Growbox ausreichend.
- **Tipp**: Programmiere die Steckdose für einen 18/6-Stunden-Zyklus (18 Stunden an, 6 Stunden aus) in der Wachstumsphase und 12/12 in der Blütephase (für Hanf). Falls das Licht dimmbar ist, passe die Intensität an die Pflanzenphase an.

#### 27/38 W Abluft
- **Hintergrund**: Die Abluft sorgt für Luftaustausch und entfernt überschüssige Feuchtigkeit und Hitze.
- **Tipp**: Schalte die Abluft ein, wenn die Luftfeuchtigkeit über 60 % (Wachstumsphase) oder 50 % (Blütephase) steigt, um Schimmel zu vermeiden. Kopple die Abluft auch an die Temperatur: Einschalten bei über 28 °C.

#### 20 W Umluft
- **Hintergrund**: Umluft verbessert die Luftzirkulation und stärkt die Pflanzenstängel.
- **Tipp**: Lass den Umluftventilator durchgehend auf niedriger Stufe laufen, um die Pflanzen nicht zu stressen.

#### 1000 W Heizlüfter
- **Hintergrund**: Ein 1000-W-Heizlüfter ist leistungsstark, aber in einer 100x100x180 cm Box muss er vorsichtig eingesetzt werden, um Überhitzung zu vermeiden.
- **Tipp**: Schalte den Heizlüfter ein, wenn die Temperatur unter 20 °C (Wachstumsphase) oder 18 °C (Blütephase) fällt. Verwende eine Hysterese (z. B. einschalten bei 20 °C, ausschalten bei 22 °C), um ständiges Ein-/Ausschalten zu vermeiden.
- **Herausforderung im Keller**: Bei 12–17 °C im Keller wird der Heizlüfter häufig laufen müssen, besonders nachts. Achte auf den Energieverbrauch und stelle sicher, dass die Box gut isoliert ist, um Wärmeverluste zu minimieren.

### 3. Optimale Werte für Hanf und Tomaten
Die folgenden Werte helfen dir, die Umweltbedingungen in der Growbox zu optimieren:

#### Temperatur
- **Wachstumsphase**:  
  - Tag: 22–28 °C  
  - Nacht: 18–22 °C  
- **Blütephase (Hanf)**:  
  - Tag: 20–26 °C  
  - Nacht: 16–20 °C  
- **Bodentemperatur**: 20–24 °C  
- **Wassertank**: 20–24 °C  
- **Stecklingshaus**: 22–25 °C  
- **Hinweis**: Da der Keller bei 12–17 °C liegt, wird der Heizlüfter entscheidend sein, um die Temperatur in der Growbox zu erhöhen.

#### Luftfeuchtigkeit
- **Wachstumsphase**: 50–70 %  
- **Blütephase**: 40–50 % (um Schimmel zu vermeiden)  
- **Stecklingshaus**: 70–80 % (hohe Feuchtigkeit fördert Wurzelbildung)  
- **Hinweis**: Die Luftfeuchtigkeit im Keller (30 %) ist sehr niedrig. In der Growbox solltest du die Luftfeuchtigkeit erhöhen, z. B. mit einem Luftbefeuchter oder durch Verdunstung (z. B. ein offenes Wasserbehälter in der Box).

#### Luftqualität (BME680)
- Achte auf plötzliche Anstiege der VOC-Werte, die auf Schimmel, CO₂-Anreicherung oder schlechte Belüftung hinweisen könnten. Stelle sicher, dass die Abluft regelmäßig frische Luft in die Box bringt.

#### Bodenfeuchtigkeit
- Halte die Bodenfeuchtigkeit bei 40–60 %, um ein Gleichgewicht zwischen Feuchtigkeit und Sauerstoffversorgung der Wurzeln zu gewährleisten. In einem kühlen Keller (12–17 °C) verdunstet Wasser langsamer, also sei vorsichtig mit Überwässerung.

---

## Nächste Schritte
- **Programmierung**: Im nächsten Abschnitt werden wir den Python-Code für den Raspberry Pi bereitstellen, um die Sensoren auszulesen und die Geräte zu steuern.
- **Visualisierung**: Wir zeigen, wie du die Daten mit Tools wie Grafana oder einer einfachen Weboberfläche visualisieren kannst.
- **Dokumentation für YouTube**: Tipps, wie du den Aufbau und die Ergebnisse für deinen YouTube-Kanal @iggyswelt präsentieren kannst, folgen in einem separaten Abschnitt.

## Mitmachen
CyberGrowPi ist ein Open-Source-Projekt, und wir freuen uns über Beiträge! Wenn du Ideen, Verbesserungen oder Erweiterungen hast, erstelle ein Issue oder einen Pull Request. Schau auch auf @iggyswelt auf YouTube vorbei, um das Projekt in Aktion zu sehen!
