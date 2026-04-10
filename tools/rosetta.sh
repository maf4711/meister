#!/bin/bash

# Überprüft, ob Apps unter Rosetta laufen und misst Startzeiten
# Voraussetzungen: macOS mit Activity Monitor und pgrep
# Ausführung: chmod +x check_rosetta.sh; ./check_rosetta.sh <App-Name> z.B. ./check_rosetta.sh "Google Chrome"

APP_NAME="$1"

if [ -z "$APP_NAME" ]; then
  echo "Benutzung: $0 <App-Name>"
  exit 1
fi

# Rosetta-Status prüfen (via Systembericht, aber automatisiert via arch)
APP_PATH=$(mdfind -name "$APP_NAME.app" | head -1)
if [ -z "$APP_PATH" ]; then
  echo "App $APP_NAME nicht gefunden."
  exit 1
fi

ARCH_INFO=$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null)
if [[ $ARCH_INFO == *"x86_64"* && $ARCH_INFO != *"arm64"* ]]; then
  echo "$APP_NAME läuft unter Rosetta 2."
else
  echo "$APP_NAME ist native ARM."
fi

# Startzeit messen (einfach, via time)
echo "Starte $APP_NAME und messe Zeit..."
start_time=$(date +%s%N)
open -a "$APP_NAME"
while ! pgrep -x "$APP_NAME" > /dev/null; do sleep 0.1; done
end_time=$(date +%s%N)
duration=$(( (end_time - start_time) / 1000000000 ))
echo "Startzeit: $duration Sekunden."

# Minimal-Test: Starte Skript mit bekannter App, erwarte Ausgabe ohne Fehler.