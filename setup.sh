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

# Update und Upgrade
echo "Aktualisiere und upgrade das System..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Installiere notwendige Pakete
echo "Installiere notwendige Pakete..."
sudo apt-get install -y \
    mjpg-streamer \
    v4l-utils \
    vlc \
    cheese \
    libv4l-dev \
    ffmpeg \
    git \
    build-essential

# Überprüfe, ob mjpg-streamer und v4l-utils korrekt installiert sind
echo "Überprüfe mjpg-streamer und v4l-utils..."
if ! command -v mjpg-streamer &> /dev/null
then
    echo "Fehler: mjpg-streamer wurde nicht gefunden!"
    exit 1
fi

if ! command -v v4l2-ctl &> /dev/null
then
    echo "Fehler: v4l-utils wurde nicht gefunden!"
    exit 1
fi

# Kamera-Tests und Vorbereitung
echo "Starte Kamera-Test..."
# Kamera auf /dev/video0 prüfen
if [ -e /dev/video0 ]; then
    echo "Kamera auf /dev/video0 gefunden."
else
    echo "Fehler: Keine Kamera auf /dev/video0 gefunden!"
    exit 1
fi

# Setze Kamera-Format und -Auflösung
echo "Setze Kamera auf 640x480 und MJPEG-Format..."
v4l2-ctl --device=/dev/video0 --set-fmt-video=width=640,height=480,pixelformat=MJPG

# Teste Video-Stream
echo "Teste Video-Stream..."
mjpg_streamer -o "output_http.so -w /usr/local/www" -i "input_uvc.so -d /dev/video0 -r 640x480 -f 30"

# Starte mjpg-streamer im Hintergrund
echo "Starte mjpg-streamer im Hintergrund..."
nohup mjpg_streamer -o "output_http.so -w /usr/local/www" -i "input_uvc.so -d /dev/video0 -r 640x480 -f 30" &

# Prüfe, ob der Stream erfolgreich läuft
if pgrep mjpg_streamer > /dev/null
then
    echo "mjpg-streamer läuft erfolgreich im Hintergrund."
else
    echo "Fehler: mjpg-streamer konnte nicht gestartet werden!"
    exit 1
fi

# Kamera-Zugriff überprüfen
echo "Überprüfe, ob andere Programme die Kamera blockieren..."
if fuser -v /dev/video0; then
    echo "Die Kamera wird von einem anderen Prozess verwendet. Bitte stoppen Sie diesen Prozess."
    exit 1
else
    echo "Kamera ist frei für Verwendung."
fi

# Optional: VLC ohne GUI starten (cvlc) für Tests
echo "Starte VLC im Kopfmodus für den Video-Stream..."
cvlc v4l2:///dev/video0 :v4l2-width=640 :v4l2-height=480 :v4l2-fps=30 :v4l2-chroma=MJPG

# Optional: Kamera in Cheese testen
echo "Möchtest du die Kamera in Cheese testen? (y/n)"
read cheese_test
if [ "$cheese_test" == "y" ]; then
    cheese
else
    echo "Cheese nicht gestartet."
fi

echo "Setup abgeschlossen. Kamera und Stream sollten jetzt korrekt laufen."
