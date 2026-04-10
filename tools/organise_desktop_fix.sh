#!/bin/bash
# ============================================================
# organise_desktop_fix.sh — Fixes für Desktop-Dateien mit Sonderzeichen
# Stand: 2026-02-23
# Ausführen: bash ~/Documents/bin/organise_desktop_fix.sh
# Nutzt find statt exakte Dateinamen (Unicode NFD/NFC safe)
# ============================================================
set -uo pipefail

DT="$HOME/Desktop"
DOC="$HOME/Documents"

log() { echo "[$(date +%H:%M:%S)] $1"; }

safe_find_mv() {
    local pattern="$1" dest="$2"
    mkdir -p "$dest"
    find "$DT" -maxdepth 1 -name "$pattern" -exec mv -n {} "$dest/" \; 2>/dev/null
}

safe_find_mv_dir() {
    local pattern="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    find "$DT" -maxdepth 1 -type d -name "$pattern" -exec mv -n {} "$dest" \; 2>/dev/null
}

log "=== Desktop-Fix: Sonderzeichen-Dateien ==="

# === GESUNDHEIT ===
log "Gesundheit..."
safe_find_mv "F*llmer_Labor*" "$DOC/Gesundheit/Labor"
safe_find_mv "befund hans karl*" "$DOC/Gesundheit/Papa Hirntumor "
safe_find_mv "befunde hans-karl*" "$DOC/Gesundheit/Befunde"
safe_find_mv_dir "befund" "$DOC/Gesundheit/Befunde/befund-ordner"
safe_find_mv "Tagesliste_Medikamente*" "$DOC/Gesundheit/Supplements"

# === FAMILIE / TAGESPFLEGE ===
log "Familie / Tagespflege..."
safe_find_mv "Ausserordentliche_Kuendigung*" "$DOC/Familie/Tagespflege"
safe_find_mv "abmeldung tagesmutter*" "$DOC/Familie/Tagespflege"
safe_find_mv_dir "Barthy Tagespflege*" "$DOC/Familie/Tagespflege/Barthy-Tagespflege"
safe_find_mv_dir "SalierP*nz" "$DOC/Familie/Tagespflege/SalierPaenz"
safe_find_mv "Einkommenserkl*rung*" "$DOC/Familie/Tagespflege"
safe_find_mv "Vorgeschlagene_Kindertagespflegen*" "$DOC/Familie/Tagespflege"
safe_find_mv "RKI_Richtlinien*" "$DOC/Familie/Tagespflege"
safe_find_mv "Einverst*ndniserkl*rung*Umzug*" "$DOC/Familie/Umzug"
safe_find_mv_dir "Umzug*" "$DOC/Familie/Umzug/Umzug-Desktop"
safe_find_mv_dir "Linda" "$DOC/Familie/Linda-Desktop"
safe_find_mv_dir "linda 4 eckertz" "$DOC/Familie/linda-4-eckertz"
safe_find_mv_dir "linda marco*" "$DOC/Familie/linda-marco"
safe_find_mv_dir "mama kurzzeitpflege" "$DOC/Familie/mama-kurzzeitpflege"
safe_find_mv_dir "kleinanzeigen" "$DOC/Familie/Kleinanzeigen/kleinanzeigen-desktop"

# Reisevollmachten
safe_find_mv "Reisevollmacht*" "$DOC/Familie/Reisevollmachten"
safe_find_mv "reisevollmacht*" "$DOC/Familie/Reisevollmachten"
safe_find_mv "lindareisepass*" "$DOC/Familie/Reisevollmachten"
safe_find_mv "dubai Reisevollmacht*" "$DOC/Familie/Reisevollmachten"

# === PERSÖNLICH ===
log "Persönlich..."
safe_find_mv "Personalausweis Marco*" "$DOC/Persönlich/Ausweise"
safe_find_mv "Ummeldung Benesisstrasse*" "$DOC/Persönlich/Ausweise"
safe_find_mv "V O L L M A C H T*" "$DOC/Persönlich/Vollmachten"
safe_find_mv "VOLL MACHT*" "$DOC/Persönlich/Vollmachten"
safe_find_mv "Vollmacht zur Ummeldung*" "$DOC/Persönlich/Vollmachten"
safe_find_mv "Fragebogen_Kennenlernen*" "$DOC/Persönlich"
safe_find_mv "Just Fit*" "$DOC/Persönlich"
safe_find_mv_dir "ME" "$DOC/Persönlich/ME"
safe_find_mv "Startseite*X.webloc" "$DOC/Persönlich"
safe_find_mv "Chats durchsuchen*" "$DOC/Persönlich"

# === FINANZEN ===
log "Finanzen..."
safe_find_mv "050925_MMM*" "$DOC/Finanzen/Investments"
safe_find_mv "290825_MMM*" "$DOC/Finanzen/Investments"
safe_find_mv "Papa_Depot*" "$DOC/Finanzen/Investments"
safe_find_mv "Investment_Masterplan*" "$DOC/Finanzen/Investments"
safe_find_mv "Die 15-17 Prozent*" "$DOC/Finanzen/Investments"
safe_find_mv "crypto HOW TO*" "$DOC/Finanzen/Investments"
safe_find_mv "ohnenamen.portfolio*" "$DOC/Finanzen/Investments"
safe_find_mv "kk abrechnung*" "$DOC/Finanzen/KK-Abrechnungen"
safe_find_mv "kk q1*" "$DOC/Finanzen/KK-Abrechnungen"
safe_find_mv "Outbank_Export*" "$DOC/Finanzen/Outbank-Exporte"
safe_find_mv "privat*Outbank*" "$DOC/Finanzen/Outbank-Exporte"
safe_find_mv "Rechnung_Foellmer*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "rechnung mtservice*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "bestellung dione*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "lg 65 invoice*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "lg.pdf" "$DOC/Finanzen/Rechnungen"
safe_find_mv "CCE_000213*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "Lackschaden*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "Subscriptions*Parallels*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "checks-2-*" "$DOC/Finanzen"
safe_find_mv "Kaufvertrag*Dreame*" "$DOC/Finanzen/Kaufvertraege"
safe_find_mv "k*ndigung hausrat*" "$DOC/Versicherung/Generali"
safe_find_mv "260202 Steuerliche*" "$DOC/Finanzen/Steuern 2025"
safe_find_mv "hundeschwimmen*" "$DOC/Finanzen/Rechnungen"
safe_find_mv "3-Antrag-auf-F*rderung*" "$DOC/Finanzen"

# === IMMOBILIEN ===
log "Immobilien..."
safe_find_mv "160114321*Herzen*K*ln*" "$DOC/Immobilien/Koeln"
safe_find_mv "51515 K*rten Mietvertrag*" "$DOC/Immobilien/Kuerten"
safe_find_mv "Angebot KVA*" "$DOC/Immobilien"
safe_find_mv "treppe_technische*" "$DOC/Immobilien"
safe_find_mv "Herd*K*chenschrank*" "$DOC/Haushalt/Kuechenschrank"
safe_find_mv "Inventar_Montenegro*" "$DOC/Immobilien/Montenegro"
safe_find_mv "Inventarliste_Deutsch*" "$DOC/Immobilien/Montenegro"
safe_find_mv "Inventory*Montenegro*" "$DOC/Immobilien/Montenegro"
safe_find_mv "Inventory Chemnitz*" "$DOC/Immobilien/Montenegro"

# === BUSINESS ===
log "Business..."
safe_find_mv "meradOS*Founder*" "$DOC/Business/MeradOS"
safe_find_mv "meradOS_Investor_Pitch*" "$DOC/Business/MeradOS/Pitch-Decks"
safe_find_mv "meradOS_Investor_Deck*" "$DOC/Business/MeradOS/Pitch-Decks"
safe_find_mv "meradOSPitch*" "$DOC/Business/MeradOS/Pitch-Decks"
safe_find_mv "meradOS_workspace*" "$DOC/Business/MeradOS/Logos"
safe_find_mv "Broker_API*" "$DOC/Business/MeradOS"
safe_find_mv "merados-healthchecker*" "$DOC/Business/MeradOS"
safe_find_mv "Pr*sentation1*" "$DOC/Business/MeradOS/Pitch-Decks"
safe_find_mv_dir "marc pitch" "$DOC/Business/MeradOS/Pitch-Decks/marc-pitch"
safe_find_mv "MM_Pitch*" "$DOC/Business/EBF-Synergy"
safe_find_mv "EBF_tradeOS*" "$DOC/Business/EBF-Synergy"
safe_find_mv_dir "F*llmer Ventures iG" "$DOC/Business/Foellmer-Ventures/Foellmer-Ventures-iG"
safe_find_mv "Domainportfolio*" "$DOC/Business/Foellmer-Ventures"
safe_find_mv "fintech_domains*" "$DOC/Business/Domains"
safe_find_mv "tradeos_pitch*" "$DOC/Business/TradeOS/Pitch-Decks"
safe_find_mv "tradeup_tradeos*" "$DOC/Business/TradeOS/Pitch-Decks"
safe_find_mv "tradeOS_autopilot*" "$DOC/Business/TradeOS/Logos"

# === HAUSHALT / TECH ===
log "Haushalt / Tech..."
safe_find_mv "PV_Autarkie*" "$DOC/Haushalt/PV-Autarkie"
safe_find_mv "Tagesplan_PV*" "$DOC/Haushalt/PV-Autarkie"
safe_find_mv_dir "dreame ls10 ultra" "$DOC/Haushalt/Dreame/dreame-ls10-ultra"
safe_find_mv_dir "ultra" "$DOC/Haushalt/Dreame/ultra"
safe_find_mv_dir "whos perfect" "$DOC/Haushalt/whos-perfect"
safe_find_mv_dir "AutoSort" "$DOC/Tech/AutoSort"
safe_find_mv_dir "gpt" "$DOC/Tech/Prompts/gpt"
safe_find_mv_dir "promptArchiv" "$DOC/Tech/Prompts/promptArchiv"
find "$DT" -maxdepth 1 -type d -name "MARCO*MASTERPROMPT*" -exec mv -n {} "$DOC/Tech/Prompts/MASTERPROMPT" \; 2>/dev/null
safe_find_mv "test.hazelrules" "$DOC/Tech/Config"

# === MEDIEN ===
log "Medien..."
safe_find_mv "Bildschirmaufnahme*" "$DOC/Medien/Videos"
safe_find_mv "benesis8*" "$DOC/Medien/Videos"
safe_find_mv "haensel*gretel*" "$DOC/Medien/Audio"
safe_find_mv "nananan*" "$DOC/Medien/Audio"
safe_find_mv "IMG_*" "$DOC/Medien/Bilder"
safe_find_mv "1757619523937*" "$DOC/Medien/Bilder"
safe_find_mv "4EDE210C*" "$DOC/Medien/Bilder"
safe_find_mv "772D3F38*" "$DOC/Medien/Bilder"
safe_find_mv "D42143*" "$DOC/Medien/Bilder"
safe_find_mv "G9a*" "$DOC/Medien/Bilder"
safe_find_mv "a7b4a948*" "$DOC/Medien/Bilder"
safe_find_mv "papa.png" "$DOC/Medien/Bilder"
safe_find_mv "mf.jpeg" "$DOC/Medien/Bilder"
safe_find_mv "ebita_hebel*" "$DOC/Medien/Bilder"
safe_find_mv "wettbewerbsvergleich*" "$DOC/Medien/Bilder"
safe_find_mv_dir "Akropolis Discographie" "$DOC/Medien/Akropolis/Discographie"
safe_find_mv "Akropolis*" "$DOC/Medien/Akropolis"
safe_find_mv "akropolis*" "$DOC/Medien/Akropolis"

# Dev-Projekte
safe_find_mv_dir "merados" "$DOC/Projekte/merados-desktop"
safe_find_mv_dir "tradeOS" "$DOC/Projekte/tradeOS-desktop"
safe_find_mv_dir "tradeOS.ai" "$DOC/Projekte/tradeOS-ai"
safe_find_mv_dir "stoxr" "$DOC/Projekte/stoxr-desktop"
safe_find_mv_dir "xcode-projects" "$DOC/Projekte/xcode-projects"

# Reisen
safe_find_mv "dubai.pdf" "$DOC/Reisen"

# Sonstige
safe_find_mv "TIME.TXT" "$DOC/Persönlich"
find "$DT" -maxdepth 1 -type d -name "O'*" -exec mv -n {} "$DOC/Persönlich/O-misc" \; 2>/dev/null

# Temp löschen
find "$DT" -maxdepth 1 -name "~\$*" -delete 2>/dev/null

# === ERGEBNIS ===
log "=== Ergebnis ==="
remaining=$(find "$DT" -maxdepth 1 ! -name "." ! -name ".DS_Store" ! -name ".localized" ! -name ".tmp*" ! -name "IB Gateway*" ! -name "IBKR Desktop*" ! -name "Trader Workstation*" | wc -l)
log "Verbleibende Dateien auf Desktop: $remaining"
if [ "$remaining" -gt 0 ]; then
    log "Details:"
    find "$DT" -maxdepth 1 ! -name "." ! -name ".DS_Store" ! -name ".localized" ! -name ".tmp*" ! -name "IB Gateway*" ! -name "IBKR Desktop*" ! -name "Trader Workstation*" -exec basename {} \; 2>/dev/null | sort
fi
log "=== FERTIG ==="
