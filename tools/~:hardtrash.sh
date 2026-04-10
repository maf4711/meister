#!/bin/bash
# hardtrash.sh — Löscht störrische Trash-Ordner auch mit iCloud-Inhalten im macOS Recovery
# Nutzung im Recovery-Terminal:
#   bash "/Volumes/Macintosh HD - Data/Users/a321/hardtrash.sh"
# Passt automatisch 'Data' vs. 'Daten' und den User-Pfad an.

set -euo pipefail

log(){ printf "%s\n" "$*"; }
ok(){ printf ">>> %s\n" "$*"; }
err(){ printf "!!! %s\n" "$*" >&2; }

# 1) Data-Volume finden (englisch/deutsch/ohne Leerzeichen)
detect_data_volume() {
  for vol in \
    "/Volumes/Macintosh HD - Data" \
    "/Volumes/Macintosh HD - Daten" \
    "/Volumes/MacintoshHD-Data" \
    "/Volumes/MacintoshHD - Data" \
    "/Volumes/MacintoshHD - Daten"
  do
    [ -d "$vol" ] && { echo "$vol"; return; }
  done
  # Fallback: best guess
  if [ -d "/Volumes" ]; then
    # Nimm das größte APFS-Volume mit "Data"/"Daten" im Namen
    guess=$(ls /Volumes | grep -Ei 'data|daten' | head -n1 || true)
    [ -n "$guess" ] && echo "/Volumes/$guess" && return
  fi
  echo ""
}

DATAVOL="$(detect_data_volume)"
[ -n "$DATAVOL" ] || { err "Konnte Data-Volume nicht finden. 'ls /Volumes' prüfen und Pfad oben ergänzen."; exit 1; }

ok "Data-Volume: $DATAVOL"

# 2) Schreibbar mounten
mount -uw "$DATAVOL" 2>/dev/null || true

# 3) User ermitteln. Standard: a321, sonst erster Ordner unter Users
USERDIR="$DATAVOL/Users/a321"
if [ ! -d "$USERDIR" ]; then
  cand=$(ls -1 "$DATAVOL/Users" 2>/dev/null | head -n1 || true)
  [ -n "$cand" ] && USERDIR="$DATAVOL/Users/$cand"
fi
[ -d "$USERDIR" ] || { err "Konnte Benutzerordner nicht finden unter $DATAVOL/Users"; exit 1; }

ok "Benutzerordner: $USERDIR"

# 4) Ziele definieren
TRASH="$USERDIR/.Trash"
TRASH_OLD="$USERDIR/Trash_old"
TARGETS=(
  "$TRASH/test"
  "$TRASH_OLD/test"
)

# 5) Versuche iCloud/Flags/ACLs zu entschärfen, wenn Ordner existiert
relax_path() {
  local p="$1"
  [ -e "$p" ] || return 0
  # Besitzer auf Benutzer setzen, ACL/Flags weg, Schreibrechte geben
  # Besitzername aus Pfad extrahieren:
  local uname
  uname="$(basename "$USERDIR")"
  chown -R "$uname":staff "$p" 2>/dev/null || true
  chmod -RN "$p" 2>/dev/null || true
  chflags -R nouchg,noschg "$p" 2>/dev/null || true
  chmod -R u+rwX "$p" 2>/dev/null || true
  # iCloud-Container umbenennen, damit keine Sonderbehandlung triggert
  if [ -d "$p/Library/Mobile Documents" ]; then
    mv "$p/Library/Mobile Documents" "$p/Library/Mobile Documents.to_delete" 2>/dev/null || true
  fi
}

# 6) Tiefen-first löschen (ohne Traversier-Fallen)
deep_delete() {
  local p="$1"
  [ -e "$p" ] || return 0
  # mehrfache Durchläufe, um Leichen loszuwerden
  for i in 1 2 3 4 5 6 7 8; do
    find "$p" -type f -exec rm -f {} + 2>/dev/null || true
    find "$p" -depth -type d -empty -delete 2>/dev/null || true
  done
  rm -rf "$p" 2>/dev/null || true
}

# 7) Löschen durchführen
ANY_EXIST=0
for T in "${TARGETS[@]}"; do
  if [ -e "$T" ]; then
    ANY_EXIST=1
    log "Bearbeite: $T"
    relax_path "$T"
    deep_delete "$T"
  fi
done

# 8) Ergebnis prüfen
RES_OK=1
for T in "${TARGETS[@]}"; do
  if [ -e "$T" ]; then
    RES_OK=0
    err "Pfad besteht noch: $T"
    # Debug-Ausgabe
    ls -leO@ "$T" 2>/dev/null || true
  fi
done

if [ $ANY_EXIST -eq 0 ]; then
  ok "Nichts zu löschen – Ziele nicht vorhanden."
  exit 0
fi

if [ $RES_OK -eq 1 ]; then
  ok "Ordner 'test' wurde vollständig gelöscht."
  # Info: aktueller Zustand anzeigen
  ls -la "$TRASH" 2>/dev/null || true
  ls -la "$TRASH_OLD" 2>/dev/null || true
  exit 0
else
  err "Ein Rest konnte nicht entfernt werden. Prüfe Volumename mit 'ls /Volumes' und Pfade."
  exit 1
fi