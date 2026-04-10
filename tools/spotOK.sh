#!/bin/bash

echo "Überprüfe Spotlight-Funktionalität..."

# Prüfe, ob Spotlight aktiviert ist
if [ "$(mdutil -s /)" == "Indexing enabled." ]; then
    echo "Spotlight-Indexierung ist aktiviert."
else
    echo "Spotlight-Indexierung ist deaktiviert."
fi

# Teste die Suchfunktion
echo "Führe eine Testsuche durch..."
result=$(mdfind -name "test" -onlyin ~ -count)
echo "Gefundene Dateien mit 'test' im Namen: $result"

# Überprüfe den Indexierungsstatus
echo "Überprüfe Indexierungsstatus..."
mdutil -s /

# Prüfe auf kürzlich indizierte Dateien
echo "Prüfe auf kürzlich indizierte Dateien..."
mdfind 'kMDItemFSContentChangeDate > $time.today(-1)'

echo "Spotlight-Funktionalitätstest abgeschlossen."
