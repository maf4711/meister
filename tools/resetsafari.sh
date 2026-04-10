# 1. Safari komplett schließen
killall Safari

# 2. Preferences zurücksetzen
defaults delete com.apple.Safari
defaults delete com.apple.SafariTechnologyPreview  # falls vorhanden

# 3. Caches & Daten löschen (History, Cookies, etc.)
rm -rf ~/Library/Safari/*
rm -rf ~/Library/Containers/com.apple.Safari*
rm -rf ~/Library/Caches/com.apple.Safari*

# 4. Optional: WebKit-Caches
rm -rf ~/Library/Caches/com.apple.WebKit*

# 5. Safari neu starten
open -a Safari