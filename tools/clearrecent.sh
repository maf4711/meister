#!/bin/bash

echo "Erweiterter Löschprozess für zuletzt verwendete Elemente gestartet..."

# Funktion: Löschen der Shared File Lists (beinhaltet Menü „Zuletzt benutzt“)
clear_shared_file_lists() {
    echo "Lösche Shared File Lists..."
    rm -f ~/Library/Application\ Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.*.sfl2
    echo "Shared File Lists gelöscht."
}

# Funktion: Löschen des UserCaches (zusätzliche Bereinigung)
clear_user_caches() {
    echo "Leere Benutzer-Caches..."
    rm -rf ~/Library/Caches/*
    echo "Benutzer-Caches geleert."
}

# Funktion: Löschen der spezifischen Finder- und Dock-Einstellungen
clear_finder_dock_recent_items() {
    echo "Zurücksetzen der Einstellungen für „Zuletzt benutzt“..."
    defaults delete com.apple.recentitems
    defaults delete com.apple.dock recent-apps
    killall Dock
    echo "Einstellungen für „Zuletzt benutzt“ und Dock zurückgesetzt."
}

# Funktion: Neustart von Diensten
restart_services() {
    echo "Starte betroffene Dienste neu..."
    killall Finder
    killall Dock
    echo "Finder und Dock neu gestartet."
}

# Hauptausführung
clear_shared_file_lists
clear_user_caches
clear_finder_dock_recent_items
restart_services

echo "Löschen abgeschlossen. Die Einträge im Menü sollten entfernt sein."