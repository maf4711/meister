#!/bin/bash
# shellcheck disable=SC2155,SC2329
# ==============================================================================
# meister2026.sh
#
# Meister - macOS Wartung, Update & Self-Healing
# Version: 0.09
# Stand: 2026-03-22
#
# NEU in v0.09:
#  - AI-Heal: Ollama als Fallback wenn Known-Fix versagt
#    (Modul fehlgeschlagen → Known-Fix? → nein → Ollama fragen → Fix ausfuehren → Retry)
#    Sicherheitscheck blockt gefaehrliche Befehle (rm -rf /, mkfs, dd, etc.)
#  - ENTFERNT: Git-Backup nach iCloud (iCloud + .git = Sync-Konflikte, GitHub ist das Backup)
#
# v0.09 (Elon-Algorithmus Cleanup):
#  - Gestrichen: Lynis, RAM Purge, TCP/sysctl Tuning, fdupes, Mail-Check,
#    Recent Items, Launch Services rebuild, GUI-Animationen, Power-Override,
#    AI-Summary, AI-Performance-Tipps, doppelter Spotlight-Check
#  - Config-Parser vereinfacht (case/esac → Loop)
#  - LaunchAgent: 1 Template statt 2
#  - Deep Clean: 14 statt 20 Sub-Tasks
#  - Performance: 11 statt 16 Sub-Tasks
#  - ~1000 Zeilen weniger, gleiche Funktionalitaet
#
# Aeltere Versionen: siehe git log
#   10. Dry-Run-Modus (-n Flag)
#   11. Netzwerk-Check mit mehreren Endpunkten
#   12. brew --greedy statt --force
#   13. Config-Datei (~/.meister/config)
#   14. Logfile nach ~/.meister/meister.log verschoben
#   15. ClamAV: bessere Exclude-Patterns
#   16. Run-History in ~/.meister/history.log
#
# Usage: ./meister2026.sh [flags]
#   (ohne Flags)  AUTO-DETECT: analysiert Mac, aktiviert was noetig ist
#   -a  ALLE Module erzwingen     -A  ClamAV (sudo)
#   -X  Xcode clean               -M  Monolingual
#   -T  Trash leeren              -S  Sudo tasks
#   -C  Caches (sudo)             -L  Grosse Dateien
#   -O  LM Studio sync            -c  NUR ClamAV
#   -P  Performance-Tuning        -G  Git Repos
#   -H  Health Dashboard          -n  Dry-Run
#   -q  Quiet (nur Warns/Fixes)  -I  LaunchAgent install
#   -h  Hilfe
# ==============================================================================

#############################
# 1. CONFIGURATION
#############################

MEISTER_DIR="$HOME/.meister"
mkdir -p "$MEISTER_DIR/patches" "$MEISTER_DIR/output" 2>/dev/null

# Defaults
LOGFILE="$MEISTER_DIR/meister.log"
LOCKFILE="$MEISTER_DIR/meister.lock"
DISK_USAGE_THRESHOLD=80
LARGE_FILE_SIZE_MB=1000
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-coder:30b}"
OLLAMA_FALLBACK_MODEL="llama3:latest"
OLLAMA_ENABLED=true
NET_CHECK_HOSTS="google.com apple.com cloudflare.com"

# Fix #78: Deep Clean Config-Gating (via ~/.meister/config steuerbar)
CLEAN_PKG_CACHES=true         # npm/pip/yarn/gem Caches
CLEAN_DEV_CACHES=true         # CocoaPods/SPM/Carthage
CLEAN_PARALLELS_LOGS=true     # Parallels VM-Logs
CLEAN_FONT_CACHE=true         # Font-Cache + QuickLook-Cache

# Fix #93: macOS Performance-Optimierung (via ~/.meister/config steuerbar)
PERF_SPOTLIGHT_EXCLUDE=true    # Dev-Verzeichnisse von Spotlight ausschliessen
PERF_DISABLE_AGENTS=true       # Unnoetige User LaunchAgents deaktivieren
PERF_CLEAN_OLLAMA=true         # Unbenutzte Ollama-Modelle loeschen
OLLAMA_KEEP_MODELS="qwen3-coder:30b llama3.2:latest"  # Modelle die behalten werden

# Spotlight Fix (automatisch bei jedem Lauf)
SPOTLIGHT_FIX_ENABLED=true         # Spotlight-Diagnose und Reparatur
SPOTLIGHT_MDS_CPU_THRESHOLD=30     # mds CPU-Schwelle fuer Neustart (%)
SPOTLIGHT_REINDEX_ON_ERROR=true    # Automatisch reindexieren bei Fehler

# iCloud Sync Fix (automatisch bei jedem Lauf)
ICLOUD_FIX_ENABLED=true            # iCloud-Diagnose und Reparatur
ICLOUD_GHOST_DIRS_CLEAN=true       # Leere Geister-Ordner in HOME entfernen
ICLOUD_STUBS_SCAN=true             # Korrupte iCloud-Stubs erkennen (65535 links)
ICLOUD_STUBS_DELETE=false          # Korrupte Stubs automatisch loeschen (default: aus, Sicherheit)
ICLOUD_RESTART_BIRD=true           # bird-Daemon neustarten bei Problemen
ICLOUD_ORPHAN_CONTAINERS_WARN=true # Verwaiste CloudKit-Container melden

# Self-Healing v0.06: Automatische Reparatur fuer alle Warnings
SELFHEAL_APPSTORE_OPEN=true        # App Store oeffnen bei fehlendem Login
SELFHEAL_FDA_OPEN=true             # Datenschutz-Einstellungen oeffnen fuer FDA
SELFHEAL_ORPHAN_PREFS=true         # Verwaiste Preferences sichern + loeschen
SELFHEAL_ICLOUD_CONTAINERS=true    # Verwaiste iCloud-Container loeschen
SELFHEAL_GIT_AUTOCOMMIT=true       # Uncommitted changes auto-committen
SELFHEAL_PERF_AUTO=true            # Performance-Optimierungen automatisch anwenden

# Git Repo Management (via -G Flag aktiviert)
GIT_AUTO_PUSH=true                          # Unpushed Commits automatisch pushen
GIT_REPO_SEARCH_PATHS="$HOME/Documents $HOME/Developer"  # Suchpfade fuer Repos
GIT_REPO_MAXDEPTH=5                         # Max Tiefe fuer Repo-Suche
# GIT_BACKUP_DIR/RETENTION/EXCLUDE entfernt (v0.09) - GitHub ist das Backup

# LaunchAgents die deaktiviert werden sollen (Teilmatch auf plist-Name)
PERF_DISABLE_AGENT_PATTERNS="com.google.GoogleUpdater com.google.keystone com.macpaw.CleanMyMac com.bluebubbles.server"

# Benannte Konstanten (Fix #40)
LOG_MAX_SIZE=1048576          # 1MB - Log-Rotation Schwelle
LOG_GENERATIONS=3             # Anzahl rotierter Logs
OLLAMA_STARTUP_WAIT=15        # Sekunden Warten auf Ollama-Server
LOG_CAPTURE_LINES=50          # Zeilen fuer Fehleranalyse aus Log
DISK_CRITICAL_THRESHOLD=95    # Prozent - Notfall-Cleanup Schwelle

# Fix #141: Tracken ob Meister Ollama selbst gestartet hat
OLLAMA_STARTED_BY_US=false

# Fix #144: Auto-Detect Schwellwerte (via ~/.meister/config steuerbar)
# Security Suite Konfiguration
SECURITY_PERSISTENCE_AUDIT=true        # LaunchAgent/Daemon Integritaetscheck
SECURITY_TCC_AUDIT=true                # Datenschutz-Berechtigungen pruefen

# Docker + LaunchAgent Defaults
CLEAN_DOCKER=true                      # Docker Cleanup
LAUNCHAGENT_SCHEDULE="weekly"          # daily/weekly/monthly

AUTO_DETECT=true                       # Automatische Erkennung aktiviert
AUTO_XCODE_THRESHOLD_MB=500            # DerivedData ab dieser Groesse loeschen
AUTO_TRASH_THRESHOLD_ITEMS=50          # Papierkorb ab X Elementen leeren
AUTO_TRASH_THRESHOLD_MB=500            # Papierkorb ab X MB leeren
AUTO_CACHE_THRESHOLD_MB=5000           # User Caches ab X MB loeschen
AUTO_PERIODIC_INTERVAL_DAYS=7          # periodic scripts wenn letzter > X Tage her

# Config-Datei laden (ueberschreibt Defaults)
MEISTER_CONFIG="$MEISTER_DIR/config"
if [ -f "$MEISTER_CONFIG" ]; then
    # Erlaubte Config-Keys nach Typ
    _BOOL_KEYS=" CLEAN_PKG_CACHES CLEAN_DEV_CACHES CLEAN_PARALLELS_LOGS CLEAN_FONT_CACHE CLEAN_DOCKER PERF_SPOTLIGHT_EXCLUDE PERF_DISABLE_AGENTS PERF_CLEAN_OLLAMA SPOTLIGHT_FIX_ENABLED SPOTLIGHT_REINDEX_ON_ERROR ICLOUD_FIX_ENABLED ICLOUD_GHOST_DIRS_CLEAN ICLOUD_STUBS_SCAN ICLOUD_STUBS_DELETE ICLOUD_RESTART_BIRD ICLOUD_ORPHAN_CONTAINERS_WARN SELFHEAL_APPSTORE_OPEN SELFHEAL_FDA_OPEN SELFHEAL_ORPHAN_PREFS SELFHEAL_ICLOUD_CONTAINERS SELFHEAL_GIT_AUTOCOMMIT SELFHEAL_PERF_AUTO SECURITY_PERSISTENCE_AUDIT SECURITY_TCC_AUDIT AUTO_DETECT GIT_AUTO_PUSH "
    _NUM_KEYS=" DISK_USAGE_THRESHOLD LARGE_FILE_SIZE_MB SPOTLIGHT_MDS_CPU_THRESHOLD AUTO_XCODE_THRESHOLD_MB AUTO_TRASH_THRESHOLD_ITEMS AUTO_TRASH_THRESHOLD_MB AUTO_CACHE_THRESHOLD_MB AUTO_PERIODIC_INTERVAL_DAYS GIT_REPO_MAXDEPTH "
    _STR_KEYS=" OLLAMA_MODEL OLLAMA_FALLBACK_MODEL OLLAMA_URL NET_CHECK_HOSTS OLLAMA_KEEP_MODELS PERF_DISABLE_AGENT_PATTERNS GIT_REPO_SEARCH_PATHS LAUNCHAGENT_SCHEDULE "

    while IFS='=' read -r key value; do
        key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
        [ -z "$key" ] || [ "${key:0:1}" = "#" ] && continue
        if [[ " $_BOOL_KEYS " == *" $key "* ]]; then
            [[ "$value" =~ ^(true|false)$ ]] && declare "$key=$value"
        elif [[ " $_NUM_KEYS " == *" $key "* ]]; then
            [[ "$value" =~ ^[0-9]+$ ]] && declare "$key=$value"
        elif [[ " $_STR_KEYS " == *" $key "* ]]; then
            declare "$key=$value"
        fi
    done < "$MEISTER_CONFIG"
fi

# Report Arrays
declare -a REPORT_SUCCESS
declare -a REPORT_FIXED
declare -a REPORT_WARNINGS
declare -a REPORT_ERRORS
SCRIPT_START_TIME=$(date +%s)

# Fix #84/#89: Gecachte Werte (einmaliger Aufruf, spart wiederholte Forks)
_OLLAMA_LIST_CACHE=""

MODULE_STEP=0
MODULE_TOTAL=0
SUDO_KEEPALIVE_PID=""
INTERRUPTED=false

# Flags
CLEAN_XCODE=false
EMPTY_TRASH=false
RUN_SUDO_TASKS=false
CLEAN_CACHES=false
LIST_LARGE_FILES=false
NEEDS_SUDO=true  # Fix #145: Always-on Self-Healing - Sudo immer anfordern
SHOW_HEALTH=false
DRY_RUN=false
INSTALL_LAUNCHAGENT=false
RUN_PERF_TUNE=false
RUN_GIT_REPOS=false
QUIET_MODE=false

#############################
# 2. CORE HELPERS & LOGGING
#############################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Fix #112: Timestamp-Cache spart ~200+ date-Forks pro Lauf
_LOG_TS_CACHE=""
_LOG_TS_SEC=-1

log() {
    local level="$1"; shift; local msg="$*"
    # Timestamp nur neu berechnen wenn sich die Sekunde aendert ($SECONDS ist builtin, kein Fork)
    if [ "$SECONDS" != "$_LOG_TS_SEC" ]; then
        _LOG_TS_CACHE=$(date +'%Y-%m-%d %H:%M:%S')
        _LOG_TS_SEC=$SECONDS
    fi
    local ts="$_LOG_TS_CACHE"
    local color=$NC
    case "$level" in
        INFO)  color=$GREEN ;;
        WARN)  color=$YELLOW ;;
        ERROR) color=$RED ;;
        FIX)   color=$CYAN ;;
        HEAL)  color=$MAGENTA ;;
        STEP)  color=$DIM ;;
    esac
    # Quiet-Modus: nur WARN/ERROR/FIX auf Terminal
    if ! $QUIET_MODE || [[ "$level" =~ ^(WARN|ERROR|FIX)$ ]]; then
        echo -e "${color}[${level}]${NC} ${msg}"
    fi
    # Fix #91: ANSI-Strip nur wenn noetig (spart sed-Fork in ~95% der Aufrufe)
    if [[ "$msg" == *$'\033'* ]]; then
        echo "$ts - $level - $(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
    else
        echo "$ts - $level - $msg" >> "$LOGFILE"
    fi
}

section_header() {
    local title="$1"
    MODULE_STEP=$((MODULE_STEP + 1))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  [${MODULE_STEP}/${MODULE_TOTAL}] ${BOLD}${title}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

module_timer_start() {
    MODULE_START_TS=$(date +%s)
}

module_timer_stop() {
    local name="$1"
    local end_ts=$(date +%s)
    local elapsed=$((end_ts - MODULE_START_TS))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    if [ $mins -gt 0 ]; then
        log STEP "   ${name} abgeschlossen in ${mins}m ${secs}s"
    else
        log STEP "   ${name} abgeschlossen in ${secs}s"
    fi
}

report_add() {
    local type="$1"; local msg="$2"
    case "$type" in
        SUCCESS) REPORT_SUCCESS+=("$msg") ;;
        FIX)     REPORT_FIXED+=("$msg") ;;
        WARN)    REPORT_WARNINGS+=("$msg") ;;
        ERROR)   REPORT_ERRORS+=("$msg") ;;
    esac
}

command_exists() { command -v "$1" &> /dev/null; }

rotate_logs() {
    if [ -f "$LOGFILE" ]; then
        local size=$(stat -f%z "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$LOG_MAX_SIZE" ]; then
            # Fix #36: Nummerierte Rotation (3 Generationen)
            local i=$((LOG_GENERATIONS - 1))
            while [ $i -ge 1 ]; do
                [ -f "${LOGFILE}.$i" ] && mv "${LOGFILE}.$i" "${LOGFILE}.$((i + 1))"
                i=$((i - 1))
            done
            [ -f "${LOGFILE}.old" ] && mv "${LOGFILE}.old" "${LOGFILE}.1"
            mv "$LOGFILE" "${LOGFILE}.old"
            log INFO "Logfile rotiert (war $(( size / 1024 ))KB)"
        fi
    fi
    touch "$LOGFILE"
}

# Fuehrt Befehl aus, zeigt Output zeilenweise, gibt echten Exit-Code zurueck
# Fix #68: tmpfile statt PIPESTATUS (Subshell-Bug vermieden)
run_verbose() {
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] $*"
        return 0
    fi
    local tmpout
    tmpout=$(mktemp)
    "$@" > "$tmpout" 2>&1
    local rc=$?
    while IFS= read -r line; do
        [ -n "$line" ] && log STEP "   $line"
    done < "$tmpout"
    rm -f "$tmpout"
    return $rc
}

# Einfacher Dry-Run-Wrapper ohne Output-Streaming
run_or_dry() {
    if $DRY_RUN; then
        log STEP "   [DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# Fix #8: Lockfile
acquire_lock() {
    if [ -f "$LOCKFILE" ]; then
        local old_pid=$(cat "$LOCKFILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log ERROR "Meister laeuft bereits (PID: $old_pid)"
            exit 1
        else
            log WARN "Stale Lockfile entfernt (PID $old_pid nicht mehr aktiv)"
            rm -f "$LOCKFILE"
        fi
    fi
    echo $$ > "$LOCKFILE"
}

release_lock() {
    rm -f "$LOCKFILE" 2>/dev/null
}

# Fix #141: Ollama stoppen wenn von Meister gestartet
shutdown_ollama() {
    if $OLLAMA_STARTED_BY_US; then
        log INFO "Ollama wird gestoppt (von Meister gestartet)..."
        pkill -f "ollama serve" 2>/dev/null
        # Kurz warten und pruefen ob gestoppt
        local w=0
        while [ $w -lt 5 ] && pgrep -f "ollama serve" >/dev/null 2>&1; do
            sleep 1
            w=$((w + 1))
        done
        if ! pgrep -f "ollama serve" >/dev/null 2>&1; then
            log FIX "   Ollama-Server gestoppt (RAM freigegeben)"
        else
            log WARN "   Ollama-Server konnte nicht gestoppt werden"
        fi
        OLLAMA_STARTED_BY_US=false
    fi
}

# Fix #35: Vereinheitlichter Trap fuer INT/TERM/EXIT
cleanup() {
    if $INTERRUPTED; then return; fi
    INTERRUPTED=true
    # Fix #141: Ollama stoppen bevor wir aufraumen
    shutdown_ollama 2>/dev/null
    # Bei Signal (nicht normalem Exit) Report ausgeben
    if [ -n "$CLEANUP_SIGNAL" ]; then
        echo ""
        log WARN "Meister unterbrochen ($CLEANUP_SIGNAL), raeume auf..."
        print_report 2>/dev/null
        save_history 2>/dev/null
    fi
    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    rm -f "$MEISTER_DIR/output"/*_$$.log 2>/dev/null
    release_lock
}

trap 'CLEANUP_SIGNAL=INT; cleanup' INT
trap 'CLEANUP_SIGNAL=TERM; cleanup' TERM
trap 'cleanup' EXIT

#############################
# 3. OLLAMA SELF-HEALING
#############################

ollama_available() {
    [ "$OLLAMA_ENABLED" = "true" ] && curl -sf --max-time 5 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1
}

# Fix #41: Zentraler Ollama-Starter (ersetzt doppelten Code in module_ollama + main)
ensure_ollama_running() {
    local context="${1:-}"  # optionaler Kontext fuer Log-Meldungen
    if ollama_available; then
        return 0
    fi
    if ! command_exists ollama; then
        return 1
    fi
    log WARN "${context}Ollama offline - starte Server..."
    ollama serve &>/dev/null &
    local ollama_pid=$!
    local wait_count=0
    while [ $wait_count -lt "$OLLAMA_STARTUP_WAIT" ]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if curl -sf --max-time 2 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
            break
        fi
        [ $((wait_count % 5)) -eq 0 ] && log STEP "${context}   Warte auf Ollama-Server... (${wait_count}s)"
    done
    if ollama_available; then
        log FIX "${context}Ollama-Server gestartet (nach ${wait_count}s)"
        OLLAMA_ENABLED=true
        OLLAMA_STARTED_BY_US=true  # Fix #141: Merken dass wir Ollama gestartet haben
        return 0
    else
        log WARN "${context}Ollama-Server antwortet nicht nach ${OLLAMA_STARTUP_WAIT}s"
        if kill -0 "$ollama_pid" 2>/dev/null; then
            log STEP "${context}   Prozess laeuft (PID: $ollama_pid) aber API nicht erreichbar"
        else
            log WARN "${context}   Ollama-Prozess sofort beendet"
            local ollama_log="$HOME/.ollama/logs/server.log"
            if [ -f "$ollama_log" ]; then
                log STEP "${context}   Letzte Logzeilen:"
                tail -5 "$ollama_log" 2>/dev/null | while IFS= read -r line; do
                    log STEP "${context}     $line"
                done
            fi
        fi
        OLLAMA_ENABLED=false
        return 1
    fi
}

# Fix #45: Modell-Verfuegbarkeit pruefen, Auto-Pull oder Fallback
ensure_ollama_model() {
    if ! ollama_available; then return 1; fi
    local model="$OLLAMA_MODEL"
    # Modellname ohne Tag fuer grep (z.B. "qwen3-coder" aus "qwen3-coder:30b")
    if ollama_list_cached | awk 'NR>1 {print $1}' | grep -q "^${model}$"; then
        log STEP "   Modell $model verfuegbar"
        return 0
    fi
    # Modell nicht vorhanden - versuche Auto-Pull
    log WARN "   Modell $model nicht lokal verfuegbar, starte Pull..."
    if ollama pull "$model" 2>/dev/null; then
        ollama_list_invalidate
        log FIX "   Modell $model erfolgreich heruntergeladen"
        report_add FIX "Ollama: Modell $model auto-pulled"
        return 0
    fi
    # Pull fehlgeschlagen - Fallback-Modell pruefen
    if [ -n "$OLLAMA_FALLBACK_MODEL" ] && [ "$OLLAMA_FALLBACK_MODEL" != "$model" ]; then
        if ollama_list_cached | awk 'NR>1 {print $1}' | grep -q "^${OLLAMA_FALLBACK_MODEL}$"; then
            log WARN "   Fallback auf $OLLAMA_FALLBACK_MODEL (statt $model)"
            OLLAMA_MODEL="$OLLAMA_FALLBACK_MODEL"
            log STEP "   Ollama: Fallback auf $OLLAMA_FALLBACK_MODEL"
            return 0
        fi
    fi
    # Letzter Versuch: erstes verfuegbares Modell nehmen
    local first_model=$(ollama_list_cached | awk 'NR==2 {print $1}')
    if [ -n "$first_model" ]; then
        log WARN "   Fallback auf erstes verfuegbares Modell: $first_model"
        OLLAMA_MODEL="$first_model"
        log STEP "   Ollama: Fallback auf $first_model"
        return 0
    fi
    log ERROR "   Kein Ollama-Modell verfuegbar"
    OLLAMA_ENABLED=false
    return 1
}

# Fix #89: ollama list gecacht (wird nur 1x abgefragt)
ollama_list_cached() {
    if [ -z "$_OLLAMA_LIST_CACHE" ]; then
        _OLLAMA_LIST_CACHE=$(ollama list 2>/dev/null)
    fi
    echo "$_OLLAMA_LIST_CACHE"
}
# Cache invalidieren (z.B. nach pull)
ollama_list_invalidate() {
    _OLLAMA_LIST_CACHE=""
}

# AI-Heal: Ollama als Fallback wenn known_fix() versagt
ai_heal() {
    local module_name="$1"
    local error_output="$2"

    if ! ollama_available; then return 1; fi

    log HEAL "AI-Heal: Frage Ollama nach Fix fuer $module_name..."
    local prompt="Du bist ein macOS-Systemadmin. Ein Wartungsscript-Modul '$module_name' ist fehlgeschlagen.
Fehlermeldung: $error_output
Antworte NUR mit einem einzigen Shell-Befehl der das Problem fixt. Kein Erklaerungstext, nur der Befehl. Wenn kein Fix moeglich ist, antworte mit: KEIN_FIX"

    local ai_response
    ai_response=$(curl -sf --max-time 30 "${OLLAMA_URL}/api/generate" \
        -d "$(printf '{"model":"%s","prompt":"%s","stream":false}' "$OLLAMA_MODEL" "$(echo "$prompt" | sed 's/"/\\"/g; s/$/\\n/' | tr -d '\n')")" \
        2>/dev/null | sed -n 's/.*"response":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g; s/\\t/\t/g' | head -3)

    if [ -z "$ai_response" ] || echo "$ai_response" | grep -q "KEIN_FIX"; then
        log WARN "AI-Heal: Kein Fix gefunden"
        return 1
    fi

    # Sicherheitscheck: gefaehrliche Befehle blocken
    if echo "$ai_response" | grep -qiE "rm -rf /[^a-z]|mkfs|dd if=|:(){ :|> /dev/sd|shutdown|reboot|halt"; then
        log WARN "AI-Heal: Gefaehrlicher Befehl blockiert: $ai_response"
        log STEP "   AI-Heal blockiert (gefaehrlicher Befehl)"
        return 1
    fi

    log HEAL "AI-Heal Vorschlag: $ai_response"

    if $DRY_RUN; then
        log STEP "   [DRY-RUN] Wuerde ausfuehren: $ai_response"
        return 0
    fi

    # Ausfuehren mit timeout
    local ai_fix_output
    ai_fix_output=$(timeout 30 bash -c "$ai_response" 2>&1)
    local ai_rc=$?

    if [ $ai_rc -eq 0 ]; then
        log FIX "AI-Heal: Befehl erfolgreich ausgefuehrt"
        [ -n "$ai_fix_output" ] && log STEP "   Output: $(echo "$ai_fix_output" | head -3)"
        report_add FIX "$module_name via AI-Heal repariert"
        return 0
    else
        log WARN "AI-Heal: Befehl fehlgeschlagen (Exit: $ai_rc)"
        [ -n "$ai_fix_output" ] && log STEP "   Output: $(echo "$ai_fix_output" | head -3)"
        return 1
    fi
}

# Known-Fix Patterns: schnelle Fixes ohne Ollama
known_fix() {
    local module_name="$1"
    local error_output="$2"

    case "$error_output" in
        *"Could not resolve host"*|*"Failed to connect"*|*"Network is unreachable"*)
            log HEAL "Known-Fix: DNS/Netzwerk-Reset..."
            sudo -n dscacheutil -flushcache 2>/dev/null
            sudo -n killall -HUP mDNSResponder 2>/dev/null
            sleep 2
            return 0
            ;;
        *"No space left on device"*)
            log HEAL "Known-Fix: Platz schaffen..."
            rm -rf "$HOME/Library/Caches"/* 2>/dev/null
            brew cleanup -s 2>/dev/null
            return 0
            ;;
        *"shallow"*|*"fetch-pack"*|*"Could not resolve HEAD"*)
            log HEAL "Known-Fix: Homebrew Repo reparieren..."
            git -C "$(brew --repo)" fetch --unshallow 2>/dev/null
            brew update-reset 2>/dev/null
            return 0
            ;;
        *"already installed"*|*"is already an installed"*)
            log HEAL "Known-Fix: Bereits installiert, OK"
            return 0
            ;;
        *"Couldn't find remote ref"*|*"fatal: bad object"*)
            log HEAL "Known-Fix: Git-Repository Reset..."
            brew update-reset 2>/dev/null
            return 0
            ;;
        *"Error: Your CLT"*|*"xcode-select"*)
            log HEAL "Known-Fix: Xcode CLT reparieren..."
            sudo -n xcode-select --reset 2>/dev/null
            return 0
            ;;
        *"SIGTERM"*|*"Terminated"*|*"kill"*)
            log HEAL "Known-Fix: Prozess wurde beendet, Retry..."
            sleep 3
            return 0
            ;;
    esac
    return 1
}

# Fix #6: Logfile-Diff statt leerer stderr-Datei
run_module_safe() {
    local module_name="$1"
    local module_func="$2"

    section_header "$module_name"
    module_timer_start
    local log_lines_before=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)

    $module_func
    local rc=$?

    if [ $rc -eq 0 ]; then
        module_timer_stop "$module_name"
        return 0
    fi

    log ERROR "$module_name fehlgeschlagen (Exit: $rc)"
    local module_output=$(tail -n +$((log_lines_before + 1)) "$LOGFILE" 2>/dev/null | head -"$LOG_CAPTURE_LINES")

    # Known-Fix probieren + 1x Retry
    if known_fix "$module_name" "Exit: $rc. $module_output"; then
        log HEAL "Known-Fix angewendet, Retry..."
        sleep 1
        $module_func
        rc=$?
        [ $rc -eq 0 ] && report_add FIX "$module_name via Known-Fix repariert"
    fi

    # AI-Heal Fallback: Ollama fragen wenn Known-Fix nicht geholfen hat
    if [ $rc -ne 0 ] && $OLLAMA_ENABLED; then
        if ai_heal "$module_name" "Exit: $rc. $module_output"; then
            log HEAL "AI-Heal angewendet, Retry..."
            sleep 1
            $module_func
            rc=$?
        fi
    fi

    [ $rc -ne 0 ] && report_add ERROR "$module_name fehlgeschlagen"
    module_timer_stop "$module_name"
    return $rc
}

#############################
# 4. INFRASTRUCTURE
#############################

# Fix #11: Mehrere Endpunkte
check_net() {
    log INFO "Pruefe Netzwerk..."
    # Fix #114: Parallele Ping-Checks statt sequentiell (bis 6s gespart bei Fehler)
    # Fix #138: Nur Ping-PIDs abwarten, nicht ollama serve & (haengt sonst endlos)
    local _net_ok_file _ping_pids=""
    _net_ok_file=$(mktemp)
    rm -f "$_net_ok_file"
    for host in $NET_CHECK_HOSTS; do
        ( ping -c 1 -W 3 "$host" &>/dev/null && echo "$host" > "$_net_ok_file" ) &
        _ping_pids="$_ping_pids $!"
    done
    for _pid in $_ping_pids; do wait "$_pid" 2>/dev/null; done
    if [ -f "$_net_ok_file" ]; then
        local ok_host
        ok_host=$(cat "$_net_ok_file")
        rm -f "$_net_ok_file"
        log INFO "   Netzwerk OK (ping $ok_host)"
        return 0
    fi
    rm -f "$_net_ok_file" 2>/dev/null

    log STEP "   Ping fehlgeschlagen, versuche HTTPS..."
    for host in $NET_CHECK_HOSTS; do
        if curl -sf --max-time 5 "https://$host" >/dev/null 2>&1; then
            log INFO "   Netzwerk OK (HTTPS $host)"
            return 0
        fi
    done

    log ERROR "Keine Internet-Verbindung!"

    report_add ERROR "No Internet connection"
    return 1
}

ensure_brew() {
    if ! command_exists brew; then
        log WARN "Homebrew not found. Installing..."
        run_or_dry /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if command_exists brew; then
            log FIX "Homebrew installed."
            report_add FIX "Installed Homebrew"
            eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
        else
            log ERROR "Homebrew install failed."
            report_add ERROR "Homebrew missing"
            return 1
        fi
    else
        log STEP "   Homebrew gefunden: $(brew --prefix)"
    fi
    return 0
}

ensure_tool() {
    local cmd="$1"
    local pkg="$2"
    local is_cask="${3:-}"

    if command_exists "$cmd"; then
        log STEP "   Tool '$cmd' vorhanden"
        return 0
    fi

    log WARN "Tool '$cmd' fehlt. Installiere $pkg..."
    ensure_brew || return 1

    if run_or_dry brew install $is_cask "$pkg"; then
        log FIX "Installed '$pkg'."
        report_add FIX "Auto-installed: $pkg"
        return 0
    else
        log ERROR "Failed to install '$pkg'."
        report_add ERROR "Failed to install $pkg"
        return 1
    fi
}

#############################
# 5. MODULES
#############################

# ── HOMEBREW (Fix #4: korrekte Exit-Codes) ──

module_homebrew() {
    log INFO "Homebrew Wartung..."
    ensure_brew || return 1

    local brew_version=$(brew --version 2>/dev/null | head -1)
    log STEP "   Version: $brew_version"

    # brew update mit korrektem Exit-Code
    log INFO "   brew update..."
    run_verbose brew update
    local update_rc=$?
    if [ $update_rc -ne 0 ]; then
        log WARN "brew update fehlgeschlagen (Exit: $update_rc). Trying unshallow..."
        git -C "$(brew --repo)" fetch --unshallow &>/dev/null
        run_verbose brew update
        if [ $? -eq 0 ]; then
            report_add FIX "Fixed Homebrew repo (unshallow)"
        else
            log ERROR "brew update weiterhin fehlgeschlagen"
        fi
    fi

    # Outdated formulae
    log INFO "   Pruefe veraltete Formulae..."
    local outdated_formulae=$(brew outdated --formula 2>/dev/null)
    if [ -n "$outdated_formulae" ]; then
        local formula_count=$(( $(echo "$outdated_formulae" | wc -l) ))
        log INFO "   ${formula_count} veraltete Formulae:"
        echo "$outdated_formulae" | while IFS= read -r line; do
            log STEP "     - $line"
        done
    else
        log INFO "   Alle Formulae aktuell"
    fi

    # Pinned Packages loggen (kein Warning - bewusst gepinnt)
    local pinned=$(brew list --pinned 2>/dev/null)
    if [ -n "$pinned" ]; then
        local pin_count=$(( $(echo "$pinned" | wc -l) ))
        log STEP "   ${pin_count} gepinnte Formulae (bewusst uebersprungen)"
    fi

    # brew upgrade mit korrektem Exit-Code
    log INFO "   brew upgrade..."
    run_verbose brew upgrade
    if [ $? -eq 0 ]; then
        report_add SUCCESS "Homebrew Formulae upgraded"
    else
        log STEP "   Homebrew upgrade hatte Probleme (siehe Log)"
    fi

    # Fix #142: Post-Upgrade Verifikation - sind noch Formulae veraltet?
    local still_outdated_formulae=$(brew outdated --formula 2>/dev/null)
    if [ -n "$still_outdated_formulae" ]; then
        local still_count=$(( $(echo "$still_outdated_formulae" | wc -l) ))
        log WARN "   ${still_count} Formulae nach Upgrade noch veraltet - versuche Einzel-Upgrade..."
        echo "$still_outdated_formulae" | while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            local pkg_name=$(echo "$pkg" | awk '{print $1}')
            log STEP "     Retry: $pkg_name..."
            local upgrade_out
            upgrade_out=$(brew upgrade "$pkg_name" 2>&1)
            if [ $? -eq 0 ]; then
                log FIX "     $pkg_name erfolgreich aktualisiert"
                report_add FIX "brew upgrade (Retry): $pkg_name"
            else
                log WARN "     $pkg_name Upgrade fehlgeschlagen:"
                echo "$upgrade_out" | tail -3 | while IFS= read -r errline; do
                    log STEP "       $errline"
                done
                log STEP "     brew upgrade fehlgeschlagen: $pkg_name (siehe Log)"
            fi
        done
    fi

    # Outdated casks
    log INFO "   Pruefe veraltete Casks..."
    local outdated_casks=$(brew outdated --cask --greedy 2>/dev/null)
    if [ -n "$outdated_casks" ]; then
        local cask_count=$(( $(echo "$outdated_casks" | wc -l) ))
        log INFO "   ${cask_count} veraltete Casks:"
        echo "$outdated_casks" | while IFS= read -r line; do
            log STEP "     - $line"
        done
    else
        log INFO "   Alle Casks aktuell"
    fi

    # Fix #12: --greedy statt --force
    log INFO "   Upgrading Casks (--greedy)..."
    run_verbose brew upgrade --cask --greedy

    # Fix #142: Post-Upgrade Cask-Verifikation
    local still_outdated_casks=$(brew outdated --cask --greedy 2>/dev/null)
    if [ -n "$still_outdated_casks" ]; then
        local still_cask_count=$(( $(echo "$still_outdated_casks" | wc -l) ))
        log STEP "   ${still_cask_count} Casks noch veraltet (Auto-Update Apps, normal)"
        echo "$still_outdated_casks" | while IFS= read -r line; do
            log STEP "     - $line"
        done
    fi

    # Fix #23: autoremove nach upgrade
    log INFO "   Autoremove ungenutzter Dependencies..."
    local removed=$(brew autoremove 2>&1)
    if echo "$removed" | grep -q "Uninstalling"; then
        local rm_count=$(echo "$removed" | grep -c "Uninstalling")
        log FIX "   ${rm_count} ungenutzte Dependencies entfernt"
        report_add FIX "brew autoremove: ${rm_count} Pakete entfernt"
    else
        log STEP "   Keine ungenutzten Dependencies"
    fi

    log INFO "   Cleanup..."
    run_verbose brew cleanup -s
    report_add SUCCESS "Homebrew Cleanup finished"

    # Doctor-Check mit Auto-Fix (Fix #22)
    log INFO "   brew doctor..."
    local doctor_output=$(brew doctor 2>&1)
    if echo "$doctor_output" | grep -q "ready to brew"; then
        log INFO "   Homebrew ist gesund"
    else
        local warn_count=$(echo "$doctor_output" | grep -c "Warning" 2>/dev/null || echo 0)
        log WARN "   brew doctor: ${warn_count} Warnings"
        echo "$doctor_output" | grep "Warning" | head -5 | while IFS= read -r line; do
            log STEP "     $line"
        done

        # Auto-Fix: Unlinked kegs
        local did_autofix=false
        local unlinked=$(echo "$doctor_output" | grep -A20 "unlinked kegs" | grep "^  " | sed 's/^[[:space:]]*//' | head -10)
        if [ -n "$unlinked" ]; then
            log HEAL "   Auto-Fix: Unlinked Kegs linken..."
            did_autofix=true
            while IFS= read -r keg; do
                [ -z "$keg" ] && continue
                local keg_name=$(echo "$keg" | awk '{print $1}')
                if run_or_dry brew link "$keg_name" 2>/dev/null; then
                    log FIX "     Linked: $keg_name"
                    report_add FIX "brew link: $keg_name"
                else
                    log WARN "     Link fehlgeschlagen: $keg_name (versuche --overwrite)"
                    run_or_dry brew link --overwrite "$keg_name" 2>/dev/null && \
                        report_add FIX "brew link --overwrite: $keg_name"
                fi
            done <<< "$unlinked"
        fi

        # Auto-Fix: Outdated Xcode CLT
        if echo "$doctor_output" | grep -qi "command line tools.*outdated\|CLT.*update"; then
            log HEAL "   Auto-Fix: Xcode CLT Update anstossen..."
            did_autofix=true
            run_or_dry softwareupdate --install --all 2>/dev/null
            report_add FIX "Xcode CLT Update angestossen"
        fi

        # Auto-Fix: Broken symlinks
        if echo "$doctor_output" | grep -qi "broken symlinks"; then
            log HEAL "   Auto-Fix: Broken Symlinks bereinigen..."
            did_autofix=true
            brew cleanup -s 2>/dev/null
            report_add FIX "brew cleanup: Broken Symlinks bereinigt"
        fi

        # Fix #42: Re-check nur wenn tatsaechlich Auto-Fixes angewendet wurden
        if $did_autofix; then
            local doctor_recheck=$(brew doctor 2>&1)
            if echo "$doctor_recheck" | grep -q "ready to brew"; then
                log FIX "   Homebrew nach Auto-Fix gesund!"
                report_add FIX "brew doctor: Alle Warnings behoben"
            else
                local warn_remain=$(echo "$doctor_recheck" | grep -c "Warning" 2>/dev/null || echo 0)
                if [ "$warn_remain" -lt "$warn_count" ]; then
                    log FIX "   ${warn_count} -> ${warn_remain} Warnings reduziert"
                    report_add FIX "brew doctor: ${warn_count} -> ${warn_remain} Warnings"
                fi

                if [ "$warn_remain" -gt 0 ]; then
                    log STEP "   brew doctor: ${warn_remain} Warnings verbleiben (siehe Log)"
                fi
            fi
        else
            log STEP "   brew doctor: ${warn_count} Warnings (kein Auto-Fix moeglich, siehe Log)"
        fi
    fi
}

# ── MAS (APP STORE) ──

module_mas() {
    log INFO "Pruefe Mac App Store..."
    ensure_tool "mas" "mas" || return 1

    # Fix #43: Pruefen ob User im App Store eingeloggt ist
    if ! mas account &>/dev/null; then
        log WARN "   Nicht im App Store eingeloggt"
        # Fix #124: App Store oeffnen zum Anmelden
        if $SELFHEAL_APPSTORE_OPEN && ! $DRY_RUN; then
            log HEAL "   Oeffne App Store zum Anmelden..."
            open -a "App Store" 2>/dev/null
            report_add FIX "App Store: zum Anmelden geoeffnet (manuell einloggen)"
        else
            log STEP "   App Store: Nicht eingeloggt (wird bei naechstem Lauf geoeffnet)"
        fi
        return 0
    fi

    export MAS_NO_AUTO_INDEX=1

    local spotlight_marker="$MEISTER_DIR/spotlight_fixed"
    if [ ! -f "$spotlight_marker" ]; then
        log INFO "   Indexiere MAS-Apps fuer Spotlight (einmalig)..."
        local idx_count=0
        for app_dir in /Applications/*.app; do
            [ -d "$app_dir/Contents/_MASReceipt" ] || continue
            mdimport "$app_dir" &>/dev/null || true
            idx_count=$((idx_count + 1))
            log STEP "   Indexiert: $(basename "$app_dir")"
        done
        touch "$spotlight_marker"
        log FIX "Spotlight-Index fuer ${idx_count} MAS-Apps rebuilt"
        report_add FIX "Spotlight-Index fuer ${idx_count} App Store Apps repariert"
    fi

    log INFO "   Pruefe MAS-Updates..."
    local outdated=$(mas outdated 2>/dev/null)
    if [ -z "$outdated" ]; then
        log INFO "   Alle App Store Apps aktuell"
        report_add SUCCESS "App Store apps up to date"
    else
        local count=$(( $(echo "$outdated" | wc -l) ))
        log INFO "   ${count} Updates verfuegbar:"
        echo "$outdated" | while IFS= read -r line; do
            log STEP "     - $line"
        done
        log INFO "   Installiere Updates..."
        run_verbose mas upgrade
        if [ $? -eq 0 ]; then
            report_add FIX "Updated $count App Store Apps"
        else
            report_add ERROR "MAS Upgrade failed"
        fi
    fi
}

# ── OLLAMA (Fix #5: Subshell-Counter-Bug) ──

module_ollama() {
    log INFO "Pruefe Ollama..."

    if ! command_exists ollama; then
        if command_exists brew && brew list --cask ollama &>/dev/null; then
            ensure_tool "ollama" "ollama" "--cask"
        else
            log INFO "   Ollama nicht installiert. Ueberspringe."
            return 0
        fi
    fi

    if ! command_exists ollama; then return 0; fi

    # Fix #41: Zentralen Starter verwenden
    if ollama_available; then
        log INFO "   Ollama-Server laeuft"
    elif ensure_ollama_running "   "; then
        report_add FIX "Ollama-Server automatisch gestartet"
    else
        log STEP "   Ollama-Server offline"
    fi

    local models=$(ollama_list_cached | awk 'NR>1 {print $1}')
    if [ -z "$models" ]; then
        log INFO "   Keine Ollama-Modelle installiert"
        return 0
    fi

    local model_count=$(( $(echo "$models" | wc -l) ))
    log INFO "   ${model_count} Modelle gefunden"

    # Fix #5: Kein Pipe, kein Subshell-Problem
    local updated=0
    local failed=0
    for model in $models; do
        log INFO "   Pulling: $model"
        local pull_output
        pull_output=$(run_or_dry ollama pull "$model" 2>&1)
        local pull_rc=$?
        if [ $pull_rc -eq 0 ]; then
            updated=$((updated + 1))
            log STEP "     OK"
        else
            failed=$((failed + 1))
            log WARN "   Pull fehlgeschlagen: $model"
            [ -n "$pull_output" ] && log STEP "     $(echo "$pull_output" | tail -1)"
        fi
    done

    [ $updated -gt 0 ] && ollama_list_invalidate
    log INFO "   ${updated}/${model_count} Modelle aktualisiert"
    [ $failed -gt 0 ] && log WARN "   ${failed} Pulls fehlgeschlagen"
    report_add FIX "Updated $updated/$model_count Ollama models"

}

# ── GIT REPO MANAGEMENT (Fix #101-102) ──

module_git_repos() {
    log INFO "Git Repository Management..."
    local repos_found=0

    # Git-Repo-Cache: find nur 1x/Woche, danach Cache verwenden (spart 10-30s)
    local repo_cache="$MEISTER_DIR/git_repos.cache"
    local repo_list=$(mktemp)
    local cache_max_age=$((7 * 86400))  # 7 Tage
    local use_cache=false

    if [ -f "$repo_cache" ]; then
        local cache_age=$(( $(date +%s) - $(stat -f%m "$repo_cache" 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            # Cache gueltig - nur pruefen ob Pfade noch existieren
            while IFS= read -r gitdir; do
                [ -d "$gitdir" ] && echo "$gitdir"
            done < "$repo_cache" > "$repo_list"
            use_cache=true
            log STEP "   Repo-Cache verwendet (Alter: $((cache_age / 86400))d)"
        fi
    fi

    if ! $use_cache; then
        # Frischer Scan
        for search_path in $GIT_REPO_SEARCH_PATHS; do
            [ ! -d "$search_path" ] && continue
            timeout 30 find "$search_path" -maxdepth "$GIT_REPO_MAXDEPTH" -name ".git" -type d \
                -not -path "*/node_modules/*" \
                -not -path "*/.Trash/*" \
                -not -path "*/Backups/*" \
                -not -path "*/Library/Mobile Documents/*" \
                2>/dev/null
        done | sort -u > "$repo_list"
        # Cache speichern
        cp "$repo_list" "$repo_cache" 2>/dev/null
    fi

    repos_found=$(wc -l < "$repo_list")
    repos_found=${repos_found##* }
    log INFO "   ${repos_found} Repos gefunden"

    # ── [1/2] Unpushed Repos finden und pushen ──
    log STEP "   [1/2] Unpushed Repos synchronisieren..."
    local repos_pushed=0
    local repos_dirty=0
    local repos_unpushed=0
    local repos_autocommitted=0

    while IFS= read -r gitdir; do
        [ -z "$gitdir" ] && continue
        local repo_dir=$(dirname "$gitdir")
        local repo_name=$(basename "$repo_dir")

        # Fix #105/#115: timeout 5 vor ALLE git-Befehle (auch "lokale" koennen auf iCloud-Repos haengen)
        # Fix #115: KEIN Pipe nach timeout — head -1 frisst den Exit-Code 124
        local remote
        remote=$(timeout 5 git -C "$repo_dir" remote 2>/dev/null)
        if [ $? -eq 124 ]; then
            log WARN "     ${repo_name}: TIMEOUT bei git remote"
            continue
        fi
        # Nur erste Zeile verwenden (falls mehrere Remotes)
        remote=$(echo "$remote" | head -1)
        if [ -z "$remote" ]; then
            log STEP "     ${repo_name}: kein Remote, uebersprungen"
            continue
        fi

        local branch
        branch=$(timeout 5 git -C "$repo_dir" symbolic-ref --short HEAD 2>/dev/null)
        [ -z "$branch" ] && continue

        # Fix #107: git status --porcelain einmal cachen statt 2x aufrufen
        local dirty_output
        dirty_output=$(timeout 5 git -C "$repo_dir" status --porcelain 2>/dev/null)
        if [ -n "$dirty_output" ]; then
            local dirty_count
            dirty_count=$(echo "$dirty_output" | wc -l)
            dirty_count=${dirty_count##* }
            log WARN "     ${repo_name}: ${dirty_count} uncommitted changes (${branch})"
            # Self-Healing - Auto-Commit
            if $SELFHEAL_GIT_AUTOCOMMIT && ! $DRY_RUN; then
                local commit_msg="[meister] auto-commit: ${dirty_count} changes in ${repo_name}"
                timeout 10 git -C "$repo_dir" add -A 2>/dev/null
                if timeout 10 git -C "$repo_dir" commit -m "$commit_msg" 2>/dev/null; then
                    log FIX "     ${repo_name}: Auto-Commit erfolgreich"
                    repos_autocommitted=$((repos_autocommitted + 1))
                else
                    log WARN "     ${repo_name}: Auto-Commit fehlgeschlagen"
                    repos_dirty=$((repos_dirty + 1))
                fi
            else
                repos_dirty=$((repos_dirty + 1))
            fi
        fi

        # Fix #105: Upstream-Check mit timeout (kann Netzwerk brauchen)
        local upstream
        upstream=$(timeout 5 git -C "$repo_dir" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null)
        if [ -z "$upstream" ]; then
            local remote_branch="${remote}/${branch}"
            local remote_exists
            remote_exists=$(timeout 5 git -C "$repo_dir" rev-parse --verify "$remote_branch" 2>/dev/null)
            [ -z "$remote_exists" ] && continue
            upstream="$remote_branch"
        fi

        # Fix #105: Log-Vergleich mit timeout
        local unpushed_output
        unpushed_output=$(timeout 5 git -C "$repo_dir" log "${upstream}..HEAD" --oneline 2>/dev/null)
        local unpushed=0
        [ -n "$unpushed_output" ] && unpushed=$(echo "$unpushed_output" | wc -l) && unpushed=${unpushed##* }
        if [ "${unpushed:-0}" -gt 0 ]; then
            repos_unpushed=$((repos_unpushed + 1))
            if $GIT_AUTO_PUSH; then
                log STEP "     ${repo_name}: ${unpushed} Commits pushen (${branch} -> ${remote})..."
                local push_output
                # Fix #105: Push mit timeout 30 (braucht mehr Zeit als Check)
                push_output=$(run_or_dry timeout 30 git -C "$repo_dir" push "$remote" "$branch" 2>&1)
                local push_rc=$?
                if [ $push_rc -eq 0 ]; then
                    log FIX "     ${repo_name}: ${unpushed} Commits erfolgreich gepusht"
                    repos_pushed=$((repos_pushed + 1))
                elif [ $push_rc -eq 124 ]; then
                    log ERROR "     ${repo_name}: Push Timeout (>30s)"
                else
                    log ERROR "     ${repo_name}: Push fehlgeschlagen"
                    [ -n "$push_output" ] && log STEP "       $(echo "$push_output" | tail -1)"
                fi
            else
                log WARN "     ${repo_name}: ${unpushed} unpushed Commits (${branch}) [-G zum Pushen]"
            fi
        fi
    done < "$repo_list"

    log INFO "   Push-Ergebnis: ${repos_pushed} gepusht, ${repos_unpushed} hatten Aenderungen, ${repos_dirty} dirty, ${repos_autocommitted} auto-committed"
    [ "$repos_pushed" -gt 0 ] && report_add FIX "Git: ${repos_pushed} Repos gepusht"
    [ "$repos_autocommitted" -gt 0 ] && report_add FIX "Git: ${repos_autocommitted} Repos auto-committed"
    [ "$repos_dirty" -gt 0 ] && log INFO "   Git: ${repos_dirty} Repos mit uncommitted changes"
    [ "$repos_unpushed" -gt "$repos_pushed" ] && \
        log INFO "   Git: $((repos_unpushed - repos_pushed)) Repos noch unpushed"

    # iCloud Git Backup entfernt (v0.09): Git Repos gehoeren auf GitHub, nicht in iCloud.
    # iCloud + .git = Sync-Konflikte, Lock-Files, kaputte Repos.

    rm -f "$repo_list"
}

# ── CLAMAV (Fix #15: bessere Excludes) ──

# Fix #147: ClamAV durch macOS-Bordmittel ersetzt (XProtect, Gatekeeper, MRT)
# ClamAV duplizierte nur was macOS seit Ventura nativ macht, brauchte 20+ Minuten,
# hatte staendig Permission-Probleme und fand praktisch nie was Neues.
module_xprotect() {
    log INFO "macOS Security Check (XProtect/Gatekeeper/MRT)..."
    local issues=0

    # 1. Gatekeeper aktiv?
    local gk_status
    gk_status=$(spctl --status 2>&1)
    if echo "$gk_status" | grep -q "enabled"; then
        log STEP "   Gatekeeper: aktiv"
    else
        log ERROR "   Gatekeeper: DEAKTIVIERT!"
        issues=$((issues + 1))
        if ! $DRY_RUN; then
            sudo spctl --master-enable 2>/dev/null && log FIX "   Gatekeeper reaktiviert" && \
                report_add FIX "Gatekeeper reaktiviert"
        fi
    fi

    # 2. XProtect-Version und Aktualitaet
    local xp_bundle="/Library/Apple/System/Library/CoreServices/XProtect.bundle"
    if [ -d "$xp_bundle" ]; then
        local xp_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$xp_bundle/Contents/Info.plist" 2>/dev/null)
        log STEP "   XProtect: Version ${xp_version:-unbekannt}"

        # Alter der Signaturen pruefen
        local xp_mod=$(stat -f %m "$xp_bundle/Contents/Resources/XProtect.yara" 2>/dev/null || echo 0)
        local now=$(date +%s)
        local xp_age_days=$(( (now - xp_mod) / 86400 ))
        if [ "$xp_age_days" -gt 14 ]; then
            log WARN "   XProtect-Signaturen: ${xp_age_days} Tage alt (>14)"
            issues=$((issues + 1))
            log INFO "   XProtect-Signaturen ${xp_age_days} Tage alt"
        else
            log STEP "   XProtect-Signaturen: ${xp_age_days} Tage alt (OK)"
        fi
    else
        log ERROR "   XProtect-Bundle nicht gefunden!"
        issues=$((issues + 1))
        report_add ERROR "XProtect-Bundle fehlt"
    fi

    # 3. XProtect Remediator (Background-Scanner seit Ventura)
    local xpr_dir="/Library/Apple/System/Library/CoreServices/XProtect.app"
    if [ -d "$xpr_dir" ]; then
        local xpr_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$xpr_dir/Contents/Info.plist" 2>/dev/null)
        log STEP "   XProtect Remediator: Version ${xpr_version:-unbekannt}"

        # Letzter Scan via XProtect Remediator
        local xpr_last=$(log show --predicate 'subsystem == "com.apple.XProtectFramework"' --last 24h --style compact 2>/dev/null | tail -1)
        if [ -n "$xpr_last" ]; then
            log STEP "   XProtect Remediator: Scan in letzten 24h gefunden"
        else
            log STEP "   XProtect Remediator: kein Scan in letzten 24h (normal bei niedrigem Risiko)"
        fi
    else
        log WARN "   XProtect Remediator nicht vorhanden (macOS < Ventura?)"
    fi

    # 4. MRT (Malware Removal Tool)
    local mrt_path="/Library/Apple/System/Library/CoreServices/MRT.app"
    if [ -d "$mrt_path" ]; then
        local mrt_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$mrt_path/Contents/Info.plist" 2>/dev/null)
        log STEP "   MRT: Version ${mrt_version:-unbekannt}"
    else
        log STEP "   MRT: nicht vorhanden (durch XProtect Remediator ersetzt)"
    fi

    # 5. SIP (System Integrity Protection)
    local sip_status
    sip_status=$(csrutil status 2>&1)
    if echo "$sip_status" | grep -q "enabled"; then
        log STEP "   SIP: aktiv"
    else
        log ERROR "   SIP: DEAKTIVIERT!"
        issues=$((issues + 1))
        report_add ERROR "SIP deaktiviert - Sicherheitsrisiko!"
    fi

    # 6. Firewall
    local fw_status
    fw_status=$(sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
    if echo "$fw_status" | grep -q "enabled"; then
        log STEP "   Firewall: aktiv"
    else
        log WARN "   Firewall: deaktiviert"
        if ! $DRY_RUN; then
            sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null && \
                log FIX "   Firewall aktiviert" && \
                report_add FIX "macOS Firewall aktiviert"
        fi
    fi

    if [ "$issues" -eq 0 ]; then
        report_add SUCCESS "macOS Security: XProtect + Gatekeeper + SIP OK"
    else
        log INFO "   macOS Security: ${issues} Hinweise (siehe Log)"
    fi
}

#############################
# 5b. SECURITY SUITE (Fix #145-#149)
#############################

# ── [146] LAUNCHDAEMON/LAUNCHAGENT INTEGRITAETSCHECK ──

module_persistence_audit() {
    log INFO "Persistence-Audit (LaunchAgents/Daemons)..."

    local suspicious=0
    local total_checked=0
    local findings=""

    # Bekannte Apple/System Bundle-IDs (Whitelist)
    local apple_pattern="^com\.apple\."
    local known_safe="com.meister|com.google.keystone|com.microsoft|com.docker|com.parallels|com.adobe|com.spotify|com.dropbox|com.1password|com.jetbrains|com.brew|homebrew|com.valvesoftware|com.jamf|com.nordvpn|com.bluebubbles|com.gytpol"

    # Alle LaunchAgent/Daemon Verzeichnisse pruefen
    local -a plist_dirs=(
        "$HOME/Library/LaunchAgents"
        "/Library/LaunchAgents"
        "/Library/LaunchDaemons"
    )

    for plist_dir in "${plist_dirs[@]}"; do
        [ ! -d "$plist_dir" ] && continue
        log STEP "   Pruefe: $plist_dir"

        while IFS= read -r -d '' plist; do
            total_checked=$((total_checked + 1))
            local plist_name=$(basename "$plist")
            local label=""
            local program=""

            # Label und ProgramArguments extrahieren
            label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null)
            program=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null)
            [ -z "$program" ] && program=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null)

            # Apple-eigene ueberspringen
            if [[ "$label" =~ $apple_pattern ]]; then
                continue
            fi

            # Bekannte sichere ueberspringen
            if echo "$label" | grep -qE "$known_safe"; then
                continue
            fi

            local issues=""

            # Check 1: Binary existiert?
            if [ -n "$program" ] && [ ! -f "$program" ] && [ ! -x "$program" ]; then
                issues="${issues}Binary fehlt ($program); "
            fi

            # Check 2: Binary an verdaechtigem Ort?
            if [ -n "$program" ]; then
                case "$program" in
                    /tmp/*|/var/tmp/*|/private/tmp/*)
                        issues="${issues}Binary in /tmp (verdaechtig); " ;;
                    "$HOME"/.*/*|"$HOME"/.*)
                        # Versteckter Pfad - nur warnen wenn nicht bekannt
                        if ! echo "$program" | grep -qE "\.(claude|ollama|nvm|npm|cargo|rustup|docker)/"; then
                            issues="${issues}Binary in verstecktem Ordner; "
                        fi ;;
                esac
            fi

            # Check 3: RunAtLoad + KeepAlive ohne bekannten Dienst
            local run_at_load=$(/usr/libexec/PlistBuddy -c "Print :RunAtLoad" "$plist" 2>/dev/null)
            local keep_alive=$(/usr/libexec/PlistBuddy -c "Print :KeepAlive" "$plist" 2>/dev/null)
            if [ "$run_at_load" = "true" ] && [ "$keep_alive" = "true" ]; then
                if ! echo "$label" | grep -qE "$known_safe"; then
                    issues="${issues}RunAtLoad+KeepAlive (Persistent); "
                fi
            fi

            # Check 4: Plist enthaelt verdaechtige Inhalte
            local plist_content=$(cat "$plist" 2>/dev/null)
            if echo "$plist_content" | grep -qE 'curl.*\|.*sh|wget.*\|.*sh|base64.*decode'; then
                issues="${issues}VERDAECHTIG: Download+Execute Pattern; "
            fi
            if echo "$plist_content" | grep -qi 'cryptominer\|coinhive\|xmrig\|minergate'; then
                issues="${issues}VERDAECHTIG: Cryptominer-Referenz; "
            fi

            # Check 5: Plist-Signatur pruefen (Code-Signing)
            if [ -n "$program" ] && [ -f "$program" ]; then
                if ! codesign -v "$program" 2>/dev/null; then
                    issues="${issues}Binary nicht signiert; "
                fi
            fi

            if [ -n "$issues" ]; then
                suspicious=$((suspicious + 1))
                log WARN "   FUND: $plist_name"
                log STEP "     Label:   $label"
                log STEP "     Binary:  ${program:-unbekannt}"
                log STEP "     Problem: $issues"
                findings="${findings}\n${plist_name}: ${issues}"
            fi
        done < <(find "$plist_dir" -name "*.plist" -print0 2>/dev/null)
    done

    if [ "$suspicious" -gt 0 ]; then
        log INFO "   Persistence-Audit: ${suspicious}/${total_checked} Eintraege geprueft (siehe Log)"
    else
        report_add SUCCESS "Persistence-Audit: ${total_checked} Eintraege geprueft, alle OK"
    fi
    log INFO "   ${total_checked} Plists geprueft, ${suspicious} verdaechtig"
}

# ── [148] TCC-AUDIT (Datenschutz-Berechtigungen) ──

module_tcc_audit() {
    log INFO "TCC-Audit (Datenschutz-Berechtigungen)..."

    local tcc_findings=0

    # TCC-Datenbank Pfade
    local user_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    local system_tcc="/Library/Application Support/com.apple.TCC/TCC.db"

    # Berechtigungs-Typen die kritisch sind
    # kTCCServiceAccessibility = kann Tastatur/Maus steuern
    # kTCCServiceSystemPolicyAllFiles = Full Disk Access
    # kTCCServiceScreenCapture = Bildschirm aufnehmen
    # kTCCServiceMicrophone = Mikrofon
    # kTCCServiceCamera = Kamera
    # kTCCServiceSystemPolicySysAdminFiles = System-Admin-Dateien

    local -a critical_services=(
        "kTCCServiceAccessibility:Bedienungshilfen (kann Tastatur/Maus steuern)"
        "kTCCServiceSystemPolicyAllFiles:Full Disk Access"
        "kTCCServiceScreenCapture:Bildschirmaufnahme"
        "kTCCServiceMicrophone:Mikrofon"
        "kTCCServiceCamera:Kamera"
        "kTCCServiceSystemPolicySysAdminFiles:System-Admin-Dateien"
        "kTCCServiceAppleEvents:Apple Events (Fernsteuerung)"
    )

    # User-TCC-Datenbank lesen
    if [ -f "$user_tcc" ]; then
        log STEP "   Lese User-Berechtigungen..."

        for service_entry in "${critical_services[@]}"; do
            local service="${service_entry%%:*}"
            local service_name="${service_entry#*:}"

            # Alle Apps mit dieser Berechtigung abfragen (allowed=1)
            local apps
            apps=$(sqlite3 "$user_tcc" \
                "SELECT client FROM access WHERE service='$service' AND auth_value=2;" 2>/dev/null)

            if [ -n "$apps" ]; then
                local app_count=$(echo "$apps" | wc -l | xargs)
                log STEP "   ${service_name}: ${app_count} Apps berechtigt"
                while IFS= read -r app; do
                    [ -z "$app" ] && continue
                    local app_short=$(echo "$app" | sed 's|.*/||')

                    # Pruefen ob die App noch installiert ist
                    local app_exists=true
                    if [[ "$app" == /* ]] && [ ! -e "$app" ]; then
                        app_exists=false
                    elif [[ "$app" == com.* ]]; then
                        # Bundle-ID - pruefen ob App existiert
                        if ! mdfind "kMDItemCFBundleIdentifier == '$app'" 2>/dev/null | grep -q .; then
                            app_exists=false
                        fi
                    fi

                    if ! $app_exists; then
                        log WARN "     VERWAIST: $app_short hat ${service_name} aber ist nicht mehr installiert!"
                        tcc_findings=$((tcc_findings + 1))
                    else
                        log STEP "     $app_short"
                    fi
                done <<< "$apps"
            fi
        done
    else
        log WARN "   User-TCC-Datenbank nicht lesbar (kein Full Disk Access?)"
        tcc_findings=$((tcc_findings + 1))
        if $SELFHEAL_FDA_OPEN && ! $DRY_RUN; then
            log HEAL "   Oeffne Datenschutz-Einstellungen..."
            open "x-apple.systempreferences:com.apple.preference.security?Privacy" 2>/dev/null
        fi
    fi

    # System-TCC pruefen (braucht root oder FDA)
    if [ -f "$system_tcc" ] && [ -r "$system_tcc" ]; then
        log STEP "   Lese System-Berechtigungen..."
        local fda_apps
        fda_apps=$(sqlite3 "$system_tcc" \
            "SELECT client FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2;" 2>/dev/null)
        if [ -n "$fda_apps" ]; then
            local fda_count=$(echo "$fda_apps" | wc -l | xargs)
            log STEP "   Full Disk Access (System): ${fda_count} Apps"
            echo "$fda_apps" | while IFS= read -r app; do
                [ -z "$app" ] && continue
                log STEP "     $app"
            done
        fi
    else
        log STEP "   System-TCC: nicht lesbar (braucht sudo/FDA) - uebersprungen"
    fi

    if [ "$tcc_findings" -gt 0 ]; then
        log INFO "   TCC-Audit: ${tcc_findings} Eintraege (siehe Log)"
    else
        report_add SUCCESS "TCC-Audit: alle Berechtigungen aktuell und gueltig"
    fi
}

# ── SECURITY SUITE ORCHESTRATOR ──

module_security_suite() {
    log INFO "Meister Security Suite..."

    module_xprotect
    $SECURITY_PERSISTENCE_AUDIT && module_persistence_audit || log STEP "   Persistence-Audit: deaktiviert (Config)"
    $SECURITY_TCC_AUDIT && module_tcc_audit || log STEP "   TCC-Audit: deaktiviert (Config)"

    log INFO "Security Suite abgeschlossen"
}

# ── SYSTEM & CLEANUP ──

module_system() {
    log INFO "macOS System-Update Pruefung..."
    log STEP "   Pruefe softwareupdate..."
    local sysup=$(softwareupdate -l 2>&1)

    if echo "$sysup" | grep -q "No new software"; then
        log INFO "   macOS ist aktuell"
        report_add SUCCESS "macOS is up to date"
    else
        local update_count=$(echo "$sysup" | grep -c "^\*" 2>/dev/null || echo "?")
        log WARN "   ${update_count} macOS Updates verfuegbar:"
        echo "$sysup" | grep "^\*\|Label\|Title" | while IFS= read -r line; do
            log STEP "     $line"
        done

        # Fix #26: Recommended Updates automatisch installieren (kein Restart)
        local has_restart=$(echo "$sysup" | grep -ci "restart" 2>/dev/null || echo 0)
        local has_recommended=$(echo "$sysup" | grep -ci "Recommended: YES" 2>/dev/null || echo 0)

        if [ "$has_recommended" -gt 0 ] && [ "$has_restart" -eq 0 ] && $NEEDS_SUDO; then
            log INFO "   Installiere empfohlene Updates (kein Restart noetig)..."
            run_verbose sudo softwareupdate --install --recommended --agree-to-license
            if [ $? -eq 0 ]; then
                report_add FIX "macOS Recommended Updates installiert"
            else
                log INFO "   macOS Update Installation fehlgeschlagen (manuell via Systemeinstellungen)"
            fi
        elif [ "$has_recommended" -gt 0 ] && [ "$has_restart" -eq 0 ]; then
            log WARN "   Empfohlene Updates verfuegbar (sudo noetig: -S oder -a)"
            log INFO "   macOS Update verfuegbar (sudo noetig)"
        elif [ "$has_restart" -gt 0 ]; then
            log WARN "   Updates benoetigen Restart - ueberspringe Auto-Install"
            log INFO "   macOS Update verfuegbar (Restart noetig)"
        else
            log INFO "   macOS Update verfuegbar ($update_count)"
        fi
    fi

    # Disk-Usage Check
    local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    local disk_free=$(df -h / | awk 'NR==2 {print $4}')
    log INFO "   Disk: ${disk_pct}% belegt, ${disk_free} frei"
    if [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
        log WARN "   Disk-Usage ueber ${DISK_USAGE_THRESHOLD}%!"
        log INFO "   Disk usage: ${disk_pct}% (>${DISK_USAGE_THRESHOLD}%)"
    fi
}

module_cleanup() {
    log INFO "Bereinigung..."

    if $CLEAN_XCODE; then
        local xcpath="$HOME/Library/Developer/Xcode/DerivedData"
        if [ -d "$xcpath" ]; then
            local xc_size=$(du -sh "$xcpath" 2>/dev/null | awk '{print $1}')
            log INFO "   Loesche Xcode DerivedData ($xc_size)..."
            run_or_dry rm -rf "$xcpath"
            report_add FIX "Deleted Xcode DerivedData ($xc_size)"
        else
            log INFO "   Kein Xcode DerivedData vorhanden"
        fi
    else
        log STEP "   Xcode clean: nicht noetig (DerivedData < ${AUTO_XCODE_THRESHOLD_MB}MB)"
    fi

    if $EMPTY_TRASH; then
        local trash_count=$(( $(ls -1 "$HOME/.Trash" 2>/dev/null | wc -l) ))
        log INFO "   Leere Papierkorb ($trash_count Elemente)..."
        run_or_dry rm -rf "$HOME/.Trash"/*
        report_add FIX "Emptied Trash ($trash_count items)"
    else
        log STEP "   Papierkorb: nicht noetig (< ${AUTO_TRASH_THRESHOLD_ITEMS} Elemente)"
    fi

    if $CLEAN_CACHES; then
        local cache_size=$(du -sh "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        log INFO "   Loesche User Caches ($cache_size)..."
        run_or_dry rm -rf "$HOME/Library/Caches"/*
        report_add FIX "Cleaned User Caches ($cache_size)"
        if $NEEDS_SUDO; then
            log INFO "   Loesche System Caches (sudo)..."
            run_or_dry sudo rm -rf /Library/Caches/* /System/Library/Caches/* /private/var/tmp/*
            report_add FIX "Cleaned System Caches"
        fi
    else
        log STEP "   Cache clean: nicht noetig (< ${AUTO_CACHE_THRESHOLD_MB}MB)"
    fi

    if $LIST_LARGE_FILES; then
        log INFO "   Suche Dateien groesser ${LARGE_FILE_SIZE_MB}MB..."
        local large_files=$(find "$HOME" -xdev -type f -size +${LARGE_FILE_SIZE_MB}M -print0 2>/dev/null | xargs -0 ls -lh 2>/dev/null | awk '{print $5, $9}')
        if [ -n "$large_files" ]; then
            local lf_count=$(( $(echo "$large_files" | wc -l) ))
            log INFO "   ${lf_count} grosse Dateien gefunden:"
            echo "$large_files" | head -10 | while IFS= read -r line; do
                log STEP "     $line"
            done
            [ "$lf_count" -gt 10 ] && log STEP "     ... und $((lf_count - 10)) weitere (siehe Log)"
            echo "$large_files" >> "$LOGFILE"
        else
            log INFO "   Keine Dateien groesser ${LARGE_FILE_SIZE_MB}MB"
        fi
        report_add SUCCESS "Large files logged"
    else
        log STEP "   Grosse Dateien: nicht noetig (Disk < ${DISK_USAGE_THRESHOLD}%)"
    fi
}

#############################
# 6. DEEP CLEAN & SYSTEM-HYGIENE (Fix #54-#67)
#############################

module_deepclean() {
    log INFO "Deep Clean & System-Hygiene..."
    local total_freed=0

    # Fix #54: System-Logs aufraumen
    log STEP "   [1/14] System-Logs..."
    local user_log_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
    [ -z "$user_log_size" ] && user_log_size=0
    if [ "$user_log_size" -gt 50 ]; then
        log INFO "   User-Logs: ${user_log_size} MB - raeume auf..."
        run_or_dry find "$HOME/Library/Logs" -type f -mtime +30 -delete
        local new_size=$(du -sm "$HOME/Library/Logs" 2>/dev/null | awk '{print $1}')
        [ -z "$new_size" ] && new_size=0
        local freed=$((user_log_size - new_size))
        [ "$freed" -gt 0 ] && { total_freed=$((total_freed + freed)); log FIX "   ${freed} MB User-Logs bereinigt"; }
    else
        log STEP "   User-Logs: ${user_log_size} MB (OK)"
    fi
    if $NEEDS_SUDO; then
        local sys_log_size=$(sudo du -sm /private/var/log 2>/dev/null | awk '{print $1}')
        [ -z "$sys_log_size" ] && sys_log_size=0
        if [ "$sys_log_size" -gt 200 ]; then
            log INFO "   System-Logs: ${sys_log_size} MB - raeume auf..."
            run_or_dry sudo find /private/var/log -type f -name "*.log" -mtime +30 -delete
            run_or_dry sudo rm -rf /private/var/log/asl/*.asl 2>/dev/null
            local freed_sys=$((sys_log_size - $(sudo du -sm /private/var/log 2>/dev/null | awk '{print $1}')))
            [ "$freed_sys" -gt 0 ] 2>/dev/null && { total_freed=$((total_freed + freed_sys)); log FIX "   ${freed_sys} MB System-Logs bereinigt"; }
        else
            log STEP "   System-Logs: ${sys_log_size} MB (OK)"
        fi
    fi

    # Fix #55: DMG/PKG/ZIP in Downloads (>30 Tage)
    log STEP "   [2/14] Downloads aufraeumen..."
    local dl_junk_count=0
    local dl_junk_size=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        dl_junk_count=$((dl_junk_count + 1))
        local fsize=$(stat -f%z "$f" 2>/dev/null || echo 0)
        dl_junk_size=$((dl_junk_size + ${fsize:-0}))
    done < <(find "$HOME/Downloads" -maxdepth 1 -type f \( -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 2>/dev/null)
    if [ "$dl_junk_count" -gt 0 ]; then
        local dl_mb=$((dl_junk_size / 1048576))
        log INFO "   ${dl_junk_count} alte Installer in Downloads (${dl_mb} MB, >30 Tage)"
        run_or_dry find "$HOME/Downloads" -maxdepth 1 -type f \( -name "*.dmg" -o -name "*.pkg" -o -name "*.zip" -o -name "*.tar.gz" -o -name "*.iso" \) -mtime +30 -delete
        total_freed=$((total_freed + dl_mb))
        report_add FIX "Downloads: ${dl_junk_count} alte Installer geloescht (${dl_mb} MB)"
    else
        log STEP "   Downloads: keine alten Installer"
    fi

    # Fix #56/#85: Orphaned Preferences - Batch-mdfind statt einzeln (~50-100s gespart)
    # Fix #126: Self-Healing - Backup + Auto-Delete
    log STEP "   [3/14] Orphaned Preferences..."
    local orphan_count=0
    local installed_ids_file=$(mktemp)
    local orphan_list_file=$(mktemp)
    # Alle installierten Bundle-IDs in EINEM mdfind+mdls Aufruf sammeln
    mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | \
        xargs mdls -name kMDItemCFBundleIdentifier 2>/dev/null | \
        awk -F'"' '/kMDItemCFBundleIdentifier/ && $2 != "" {print $2}' | \
        sort -u > "$installed_ids_file"
    for plist in "$HOME/Library/Preferences"/*.plist; do
        [ ! -f "$plist" ] && continue
        local bundle_id=$(basename "$plist" .plist)
        # System-Prefs und Apple-eigene ueberspringen
        [[ "$bundle_id" == com.apple.* ]] && continue
        [[ "$bundle_id" == Apple.* ]] && continue
        [[ "$bundle_id" == loginwindow ]] && continue
        [[ "$bundle_id" == com.meister* ]] && continue
        # Fix #85: Pruefen gegen gecachte Bundle-ID-Liste (grep statt mdfind pro Plist)
        if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
            orphan_count=$((orphan_count + 1))
            echo "$plist" >> "$orphan_list_file"
            [ "$orphan_count" -le 50 ] && log STEP "     Orphan: $bundle_id"
        fi
    done
    rm -f "$installed_ids_file"
    if [ "$orphan_count" -gt 0 ]; then
        log INFO "   ${orphan_count} verwaiste Preferences gefunden"
        if $SELFHEAL_ORPHAN_PREFS && ! $DRY_RUN; then
            # Backup erstellen
            local backup_dir="$MEISTER_DIR/backups/prefs_$(date +%Y%m%d)"
            mkdir -p "$backup_dir"
            local deleted=0
            while IFS= read -r orphan_plist; do
                [ -z "$orphan_plist" ] && continue
                cp "$orphan_plist" "$backup_dir/" 2>/dev/null
                rm -f "$orphan_plist" 2>/dev/null && deleted=$((deleted + 1))
            done < "$orphan_list_file"
            log FIX "   ${deleted} verwaiste Preferences geloescht (Backup: $backup_dir)"
            report_add FIX "Deepclean: ${deleted} verwaiste Preferences geloescht (Backup in ~/.meister/backups/)"
        else
            log STEP "   ${orphan_count} verwaiste Preferences (werden bei naechstem Lauf geloescht)"
        fi
    else
        log STEP "   Keine verwaisten Preferences"
    fi
    rm -f "$orphan_list_file"

    # Fix #82: Broken Plists erkennen (parallelisiert)
    # Apple-eigene Plists (com.apple.*) werden ignoriert - Apple repariert die selbst
    log STEP "   [4/14] Broken Plists..."
    local broken_user=0
    local broken_list
    broken_list=$(find "$HOME/Library/Preferences" -name "*.plist" -not -name "com.apple.*" -print0 2>/dev/null | \
        xargs -0 -P 4 -I {} sh -c 'plutil -lint "$1" >/dev/null 2>&1 || basename "$1"' _ {} 2>/dev/null)
    if [ -n "$broken_list" ]; then
        while IFS= read -r bp; do
            [ -z "$bp" ] && continue
            broken_user=$((broken_user + 1))
            [ "$broken_user" -le 10 ] && log WARN "   Defekt: $bp"
        done <<< "$broken_list"
        [ "$broken_user" -gt 0 ] && log INFO "   ${broken_user} defekte Plists (non-Apple, siehe Log)"
    else
        log STEP "   Alle Plists OK"
    fi

    # Fix #59: Screenshots aufraumen (Desktop + Schreibtisch, >30 Tage)
    log STEP "   [5/14] Alte Screenshots..."
    local screenshot_count=0
    local screenshot_mb=0
    for dir in "$HOME/Desktop" "$HOME/Schreibtisch"; do
        [ ! -d "$dir" ] && continue
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            screenshot_count=$((screenshot_count + 1))
            local fsize=$(stat -f%z "$f" 2>/dev/null || echo 0)
            screenshot_mb=$((screenshot_mb + ${fsize:-0} / 1048576))
        done < <(find "$dir" -maxdepth 1 -type f \( -name "Screenshot*" -o -name "Bildschirmfoto*" -o -name "Screen Shot*" \) -mtime +30 2>/dev/null)
    done
    if [ "$screenshot_count" -gt 0 ]; then
        log INFO "   ${screenshot_count} alte Screenshots (${screenshot_mb} MB, >30 Tage)"
        for dir in "$HOME/Desktop" "$HOME/Schreibtisch"; do
            [ ! -d "$dir" ] && continue
            run_or_dry find "$dir" -maxdepth 1 -type f \( -name "Screenshot*" -o -name "Bildschirmfoto*" -o -name "Screen Shot*" \) -mtime +30 -delete
        done
        total_freed=$((total_freed + screenshot_mb))
        report_add FIX "Screenshots: ${screenshot_count} geloescht (${screenshot_mb} MB)"
    else
        log STEP "   Keine alten Screenshots"
    fi

    # Fix #60: Time Machine lokale Snapshots
    log STEP "   [6/14] Time Machine Snapshots..."
    local tm_snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || echo 0)
    if [ "$tm_snapshots" -gt 0 ]; then
        # Purgeable Space durch TM Snapshots berechnen
        local tm_purgeable=$(( $(tmutil listlocalsnapshots / 2>/dev/null | wc -l) ))
        log INFO "   ${tm_purgeable} lokale TM-Snapshots gefunden"
        local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        if [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
            log WARN "   Disk ${disk_pct}% voll - loesche alte TM-Snapshots..."
            # Fix #69: Korrektes Snapshot-Datum extrahieren (Format: com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local)
            tmutil listlocalsnapshots / 2>/dev/null | sed -n 's/.*TimeMachine\.\(.*\)\.local/\1/p' | while IFS= read -r snap; do
                [ -n "$snap" ] && run_or_dry sudo tmutil deletelocalsnapshots "$snap"
            done
            report_add FIX "TM-Snapshots geloescht (Disk war ${disk_pct}%)"
        else
            report_add SUCCESS "TM-Snapshots: ${tm_purgeable} vorhanden (Disk OK)"
        fi
    else
        log STEP "   Keine lokalen TM-Snapshots"
    fi

    # Fix #66: Alte iOS-Backups
    log STEP "   [7/14] iOS-Backups..."
    local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [ -d "$backup_dir" ]; then
        local backup_count=0
        local backup_total_mb=0
        while IFS= read -r d; do
            [ ! -d "$d" ] && continue
            local bsize=$(du -sm "$d" 2>/dev/null | awk '{print $1}')
            [ -z "$bsize" ] && bsize=0
            backup_count=$((backup_count + 1))
            backup_total_mb=$((backup_total_mb + bsize))
            local bname=$(basename "$d")
            log STEP "     Backup: ${bname:0:12}... (${bsize} MB)"
        done < <(find "$backup_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
        if [ "$backup_count" -gt 0 ]; then
            log INFO "   ${backup_count} iOS-Backups, gesamt ${backup_total_mb} MB"
            if [ "$backup_total_mb" -gt 10240 ]; then
                log INFO "   iOS-Backups: ${backup_total_mb} MB (${backup_count} Stueck)"
            else
                report_add SUCCESS "iOS-Backups: ${backup_count} (${backup_total_mb} MB)"
            fi
        else
            log STEP "   Keine iOS-Backups"
        fi
    else
        log STEP "   Kein iOS-Backup-Verzeichnis"
    fi

    # Fix #72: Package Manager Caches (npm/pip/yarn/gem)
    if $CLEAN_PKG_CACHES; then
        log STEP "   [8/12] Package Manager Caches..."
        local pkg_freed=0

        if command_exists npm && [ -d "$HOME/.npm" ]; then
            local npm_size=$(du -sm "$HOME/.npm" 2>/dev/null | awk '{print $1}')
            [ -z "$npm_size" ] && npm_size=0
            if [ "$npm_size" -gt 50 ]; then
                log INFO "   npm cache: ${npm_size} MB"
                run_or_dry npm cache clean --force 2>/dev/null
                pkg_freed=$((pkg_freed + npm_size))
            else
                log STEP "   npm cache: ${npm_size} MB (OK)"
            fi
        fi

        if command_exists yarn && [ -d "$HOME/.yarn/cache" ]; then
            local yarn_size=$(du -sm "$HOME/.yarn/cache" 2>/dev/null | awk '{print $1}')
            [ -z "$yarn_size" ] && yarn_size=0
            if [ "$yarn_size" -gt 50 ]; then
                log INFO "   yarn cache: ${yarn_size} MB"
                run_or_dry yarn cache clean 2>/dev/null
                pkg_freed=$((pkg_freed + yarn_size))
            fi
        fi

        if command_exists pip3; then
            local pip_dir="$HOME/Library/Caches/pip"
            if [ -d "$pip_dir" ]; then
                local pip_size=$(du -sm "$pip_dir" 2>/dev/null | awk '{print $1}')
                [ -z "$pip_size" ] && pip_size=0
                if [ "$pip_size" -gt 50 ]; then
                    log INFO "   pip cache: ${pip_size} MB"
                    run_or_dry pip3 cache purge 2>/dev/null
                    pkg_freed=$((pkg_freed + pip_size))
                fi
            fi
        fi

        if command_exists gem && [ -d "$HOME/.gem" ]; then
            local gem_size=$(du -sm "$HOME/.gem" 2>/dev/null | awk '{print $1}')
            [ -z "$gem_size" ] && gem_size=0
            if [ "$gem_size" -gt 50 ]; then
                log INFO "   gem cache: ${gem_size} MB"
                run_or_dry gem cleanup 2>/dev/null
                pkg_freed=$((pkg_freed + gem_size / 2))
            fi
        fi

        if [ "$pkg_freed" -gt 0 ]; then
            total_freed=$((total_freed + pkg_freed))
            report_add FIX "Package Caches: ${pkg_freed} MB bereinigt"
        else
            log STEP "   Alle Package Caches klein oder nicht vorhanden"
        fi
    else
        log STEP "   Package Caches: uebersprungen (Config)"
    fi

    # Fix #73: Developer Tool Caches (CocoaPods/SPM/Carthage)
    if $CLEAN_DEV_CACHES; then
        log STEP "   [9/12] Developer Tool Caches..."
        local dev_freed=0

        if [ -d "$HOME/.cocoapods/repos" ]; then
            local pods_size=$(du -sm "$HOME/.cocoapods/repos" 2>/dev/null | awk '{print $1}')
            [ -z "$pods_size" ] && pods_size=0
            if [ "$pods_size" -gt 100 ]; then
                log INFO "   CocoaPods repos: ${pods_size} MB"
                run_or_dry rm -rf "$HOME/.cocoapods/repos/trunk"
                dev_freed=$((dev_freed + pods_size / 2))
            fi
        fi

        if [ -d "$HOME/.swiftpm/cache" ]; then
            local spm_size=$(du -sm "$HOME/.swiftpm/cache" 2>/dev/null | awk '{print $1}')
            [ -z "$spm_size" ] && spm_size=0
            if [ "$spm_size" -gt 100 ]; then
                log INFO "   SPM cache: ${spm_size} MB"
                run_or_dry rm -rf "$HOME/.swiftpm/cache"/*
                dev_freed=$((dev_freed + spm_size))
            fi
        fi

        local carthage_dir="$HOME/Library/Caches/org.carthage.CarthageKit"
        if [ -d "$carthage_dir" ]; then
            local cart_size=$(du -sm "$carthage_dir" 2>/dev/null | awk '{print $1}')
            [ -z "$cart_size" ] && cart_size=0
            if [ "$cart_size" -gt 100 ]; then
                log INFO "   Carthage cache: ${cart_size} MB"
                run_or_dry rm -rf "$carthage_dir"/*
                dev_freed=$((dev_freed + cart_size))
            fi
        fi

        if [ "$dev_freed" -gt 0 ]; then
            total_freed=$((total_freed + dev_freed))
            report_add FIX "Developer Caches: ${dev_freed} MB bereinigt"
        else
            log STEP "   Alle Developer Caches klein oder nicht vorhanden"
        fi
    else
        log STEP "   Developer Caches: uebersprungen (Config)"
    fi

    # Fix #74: Docker Cleanup
    if $CLEAN_DOCKER && command_exists docker; then
        log STEP "   [10/12] Docker Cleanup..."
        if docker info &>/dev/null; then
            local stopped=$(( $(docker ps -aq --filter status=exited 2>/dev/null | wc -l) ))
            local dangling=$(( $(docker images -f "dangling=true" -q 2>/dev/null | wc -l) ))
            if [ "${stopped:-0}" -gt 0 ] || [ "${dangling:-0}" -gt 0 ]; then
                log INFO "   Docker: ${stopped} stopped containers, ${dangling} dangling images"
                run_or_dry docker container prune -f --filter "until=72h" 2>/dev/null
                run_or_dry docker image prune -f 2>/dev/null
                run_or_dry docker volume prune -f 2>/dev/null
                report_add FIX "Docker: ${stopped} Container + ${dangling} Images aufgeraeumt"
            else
                log STEP "   Docker: sauber"
            fi
        else
            log STEP "   Docker: Daemon nicht erreichbar"
        fi
    elif $CLEAN_DOCKER; then
        log STEP "   Docker: nicht installiert"
    else
        log STEP "   Docker: uebersprungen (Config: CLEAN_DOCKER=false)"
    fi

    # Fix #75: Parallels VM-Logs
    if $CLEAN_PARALLELS_LOGS && [ -d "$HOME/Library/Parallels" ]; then
        log STEP "   [11/12] Parallels VM-Logs..."
        local prl_log_count
        prl_log_count=$(( $(find "$HOME/Library/Parallels" -name "*.log" -mtime +30 2>/dev/null | wc -l) ))
        if [ "${prl_log_count:-0}" -gt 0 ]; then
            local prl_size=$(find "$HOME/Library/Parallels" -name "*.log" -mtime +30 -exec du -sm {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
            log INFO "   Parallels: ${prl_log_count} alte Logs (${prl_size:-0} MB)"
            run_or_dry find "$HOME/Library/Parallels" -name "*.log" -mtime +30 -delete
            total_freed=$((total_freed + ${prl_size:-0}))
            report_add FIX "Parallels Logs: ${prl_log_count} geloescht"
        else
            log STEP "   Parallels: keine alten Logs"
        fi
    else
        log STEP "   Parallels: uebersprungen"
    fi

    # Fix #76: Font-Cache + QuickLook-Cache rebuild
    if $CLEAN_FONT_CACHE; then
        log STEP "   [12/12] Font & QuickLook Cache..."
        # Font-Cache
        if [ -x /usr/bin/atsutil ]; then
            run_or_dry atsutil databases -remove 2>/dev/null
            log FIX "   Font-Cache neuaufgebaut"
        fi
        # QuickLook-Cache
        local ql_dir="$HOME/Library/Caches/com.apple.QuickLookDaemon"
        if [ -d "$ql_dir" ]; then
            local ql_size=$(du -sm "$ql_dir" 2>/dev/null | awk '{print $1}')
            run_or_dry rm -rf "$ql_dir"
            log FIX "   QuickLook-Cache geloescht (${ql_size:-0} MB)"
            total_freed=$((total_freed + ${ql_size:-0}))
        fi
        # qlmanage Reset
        run_or_dry qlmanage -r 2>/dev/null
        report_add FIX "Font & QuickLook Cache rebuilt"
    else
        log STEP "   Font/QuickLook Cache: uebersprungen (Config)"
    fi

    # Zusammenfassung
    if [ "$total_freed" -gt 0 ]; then
        log FIX "   Deep Clean: ${total_freed} MB insgesamt freigegeben"
        report_add FIX "Deep Clean: ${total_freed} MB freigegeben"
    fi
}

#############################
# 6c. SPOTLIGHT FIX (Fix #120)
#############################

module_spotlight_fix() {
    if ! $SPOTLIGHT_FIX_ENABLED; then
        log STEP "Spotlight Fix: uebersprungen (Config)"
        return 0
    fi

    log INFO "Spotlight Diagnose & Reparatur..."
    local fixes=0

    # ── [1/5] mds/mds_stores CPU-Verbrauch ──
    log STEP "   [1/5] mds CPU-Check..."
    local mds_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/\/mds$/ {total+=$1} END {printf "%d", total+0}')
    local mds_stores_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/mds_stores/ {total+=$1} END {printf "%d", total+0}')
    local mds_total=$((mds_cpu + mds_stores_cpu))

    if [ "$mds_total" -gt "$SPOTLIGHT_MDS_CPU_THRESHOLD" ]; then
        log WARN "   mds CPU: ${mds_total}% (mds:${mds_cpu}% mds_stores:${mds_stores_cpu}%) > Schwelle ${SPOTLIGHT_MDS_CPU_THRESHOLD}%"

        # Pruefen ob Spotlight gerade aktiv indexiert
        local indexing_status=$(mdutil -s / 2>/dev/null)
        if echo "$indexing_status" | grep -qi "Indexing enabled"; then
            # Feststellen ob normales Indexing oder Haenger
            local mds_pid=$(pgrep -x mds 2>/dev/null | head -1)
            if [ -n "$mds_pid" ]; then
                local mds_state=$(ps -p "$mds_pid" -o state= 2>/dev/null)
                if [ "$mds_state" = "R" ] || [ "$mds_state" = "R+" ]; then
                    log STEP "   mds laeuft aktiv (State: $mds_state) - normales Indexing"
                    # CPU nur hoch weil Indexing aktiv, kein Neustart noetig
                    log INFO "   Spotlight indexiert gerade aktiv (CPU: ${mds_total}%)"
                else
                    log WARN "   mds scheint zu haengen (State: ${mds_state:-?})"
                    if $NEEDS_SUDO; then
                        log FIX "   Starte mds neu..."
                        run_or_dry sudo killall mds 2>/dev/null
                        sleep 2
                        log FIX "   mds neugestartet"
                        report_add FIX "Spotlight: mds neugestartet (haengte bei ${mds_total}% CPU)"
                        fixes=$((fixes + 1))
                    else
                        log INFO "   Spotlight: mds bei ${mds_total}% CPU (sudo fuer Neustart noetig)"
                    fi
                fi
            fi
        fi
    else
        log STEP "   mds CPU: ${mds_total}% (OK)"
    fi

    # ── [2/5] Spotlight Index-Status (nur User-relevante Volumes) ──
    log STEP "   [2/5] Spotlight Index-Status..."
    local volumes_checked=0
    local volumes_broken=0
    while IFS= read -r vol; do
        [ -z "$vol" ] && continue
        # Interne APFS-System-Volumes ueberspringen (kein Spotlight erwartet)
        case "$vol" in
            /System/Volumes/VM|/System/Volumes/Preboot|/System/Volumes/Update)    continue ;;
            /System/Volumes/xarts|/System/Volumes/iSCPreboot|/System/Volumes/Hardware) continue ;;
            /System/Volumes/Data|/System/Volumes/Data/*)                          continue ;;
        esac
        volumes_checked=$((volumes_checked + 1))
        local vol_status=$(mdutil -s "$vol" 2>/dev/null)
        if echo "$vol_status" | grep -qi "error\|invalid"; then
            volumes_broken=$((volumes_broken + 1))
            log ERROR "   $vol: Spotlight-Index fehlerhaft"
            if $SPOTLIGHT_REINDEX_ON_ERROR && $NEEDS_SUDO; then
                log FIX "   Reindexiere $vol..."
                run_or_dry sudo mdutil -E "$vol" 2>/dev/null
                run_or_dry sudo mdutil -i on "$vol" 2>/dev/null
                report_add FIX "Spotlight: $vol reindexiert"
                fixes=$((fixes + 1))
            else
                log INFO "   Spotlight-Index fehlerhaft: $vol"
            fi
        elif echo "$vol_status" | grep -qi "disabled"; then
            # Nur warnen fuer Root-Volume, andere koennen gewollt deaktiviert sein
            if [ "$vol" = "/" ]; then
                log WARN "   /: Spotlight deaktiviert auf Root-Volume!"
                if $NEEDS_SUDO; then
                    run_or_dry sudo mdutil -i on / 2>/dev/null
                    log FIX "   Spotlight auf / aktiviert"
                    report_add FIX "Spotlight: Root-Volume aktiviert"
                    fixes=$((fixes + 1))
                else
                    log INFO "   Spotlight auf / deaktiviert (sudo zum Aktivieren)"
                fi
            else
                log STEP "   $vol: Spotlight deaktiviert (gewollt?)"
            fi
        fi
    done < <(df -Hl 2>/dev/null | awk 'NR>1 && $NF ~ /^\// {print $NF}')
    log STEP "   ${volumes_checked} User-Volumes geprueft, ${volumes_broken} fehlerhaft"

    # ── [3/5] Spotlight-Datenbank Integritaet ──
    log STEP "   [3/5] Spotlight-DB Integritaet..."
    local spotlight_db="/.Spotlight-V100"
    if [ -d "$spotlight_db" ]; then
        local db_size=$(du -sm "$spotlight_db" 2>/dev/null | awk '{print $1}')
        [ -z "$db_size" ] && db_size=0
        if [ "$db_size" -gt 5120 ]; then
            log WARN "   Spotlight-DB ungewoehnlich gross: ${db_size} MB (>5 GB)"
            if $SPOTLIGHT_REINDEX_ON_ERROR && $NEEDS_SUDO; then
                log FIX "   Baue Spotlight-Index neu auf..."
                run_or_dry sudo mdutil -E / 2>/dev/null
                report_add FIX "Spotlight: Index neu aufgebaut (war ${db_size} MB)"
                fixes=$((fixes + 1))
            else
                log INFO "   Spotlight-DB: ${db_size} MB (Rebuild empfohlen)"
            fi
        else
            log STEP "   Spotlight-DB: ${db_size} MB"
        fi
    else
        # Kein .Spotlight-V100 auf APFS ist normal (liegt in /var)
        local var_spotlight="/private/var/db/Spotlight-V100"
        if [ -d "$var_spotlight" ]; then
            local var_db_size=$(sudo -n du -sm "$var_spotlight" 2>/dev/null | awk '{print $1}')
            log STEP "   Spotlight-DB (APFS): ${var_db_size:-?} MB"
        else
            log STEP "   Spotlight-DB: Standard-Pfad"
        fi
    fi

    # ── [4/5] Defekte Spotlight-Plugins ──
    log STEP "   [4/5] Spotlight-Plugins..."
    local plugin_count=0
    local broken_plugins=0
    for plugin_dir in /Library/Spotlight "$HOME/Library/Spotlight"; do
        [ ! -d "$plugin_dir" ] && continue
        while IFS= read -r plugin; do
            [ -z "$plugin" ] && continue
            plugin_count=$((plugin_count + 1))
            # Plugin-Binary pruefen
            if [ -f "$plugin/Contents/Info.plist" ] && ! plutil -lint "$plugin/Contents/Info.plist" &>/dev/null; then
                broken_plugins=$((broken_plugins + 1))
                log WARN "   Defektes Plugin: $(basename "$plugin")"
            fi
        done < <(find "$plugin_dir" -maxdepth 1 -name "*.mdimporter" -type d 2>/dev/null)
    done
    if [ "$broken_plugins" -gt 0 ]; then
        log INFO "   Spotlight: ${broken_plugins} defekte Plugins"
    else
        log STEP "   ${plugin_count} Plugins OK"
    fi

    # ── [5/5] Spotlight-Exclusions Audit ──
    log STEP "   [5/5] Spotlight-Exclusions Audit..."
    local excl_list=$(defaults read /.Spotlight-V100/VolumeConfiguration Exclusions 2>/dev/null)
    if [ -n "$excl_list" ]; then
        local excl_count=$(echo "$excl_list" | grep -c '"' 2>/dev/null || echo 0)
        log STEP "   ${excl_count} Pfade von Spotlight ausgeschlossen"
    fi

    # Zusammenfassung
    if [ "$fixes" -gt 0 ]; then
        log FIX "   Spotlight: ${fixes} Reparaturen durchgefuehrt"
        report_add FIX "Spotlight Fix: ${fixes} Reparaturen"
    else
        log INFO "   Spotlight: alles OK"
        report_add SUCCESS "Spotlight: gesund"
    fi
}

#############################
# 6d. ICLOUD SYNC FIX (Fix #121)
#############################

module_icloud_fix() {
    if ! $ICLOUD_FIX_ENABLED; then
        log STEP "iCloud Fix: uebersprungen (Config)"
        return 0
    fi

    log INFO "iCloud Sync Diagnose & Reparatur..."
    local fixes=0
    local warns=0
    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

    # ── [1/6] Geister-Ordner in HOME entfernen ──
    if $ICLOUD_GHOST_DIRS_CLEAN; then
        log STEP "   [1/6] Geister-Ordner in HOME..."
        local ghost_count=0
        local ghost_list=""
        # Bekannte Ordner die in HOME NICHT sein sollten (leere iCloud-Ghosts)
        # .Trash und Standard-Ordner (Desktop, Documents etc.) ueberspringen
        while IFS= read -r dir; do
            [ -z "$dir" ] && continue
            local dirname=$(basename "$dir")
            # System-Ordner und bekannte Tools ueberspringen
            case "$dirname" in
                .Trash|.cache|.config|.local|.ssh|.gnupg|.meister|.claude|.ollama|.nvm|.npm) continue ;;
                Desktop|Documents|Downloads|Movies|Music|Pictures|Public|Library) continue ;;
                Applications|Sites|.CFUserTextEncoding) continue ;;
                go|miniforge3|Parallels|Venvs|.docker|.gradle|.cargo|.rustup) continue ;;
            esac
            # Nur wirklich leere Ordner (kein .DS_Store etc.)
            local content_count=$(find "$dir" -mindepth 1 -not -name ".DS_Store" -not -name ".localized" 2>/dev/null | head -1)
            if [ -z "$content_count" ]; then
                ghost_count=$((ghost_count + 1))
                ghost_list="${ghost_list}${dirname} "
                log WARN "     Geister-Ordner: ~/${dirname}"
                run_or_dry rmdir "$dir" 2>/dev/null || run_or_dry rm -rf "$dir" 2>/dev/null
            fi
        done < <(find "$HOME" -maxdepth 1 -type d -mindepth 1 2>/dev/null)
        if [ "$ghost_count" -gt 0 ]; then
            log FIX "   ${ghost_count} Geister-Ordner entfernt: ${ghost_list}"
            report_add FIX "iCloud: ${ghost_count} Geister-Ordner entfernt (${ghost_list})"
            fixes=$((fixes + 1))
        else
            log STEP "   Keine Geister-Ordner"
        fi
    else
        log STEP "   [1/6] Geister-Ordner: uebersprungen (Config)"
    fi

    # ── [2/6] Korrupte iCloud-Stubs erkennen ──
    if $ICLOUD_STUBS_SCAN; then
        log STEP "   [2/6] Korrupte iCloud-Stubs..."
        local stub_count=0
        # Scan-Pfade: Documents, Desktop, iCloud Drive
        local scan_paths="$HOME/Documents $HOME/Desktop"
        [ -d "$icloud_dir" ] && scan_paths="$scan_paths $icloud_dir"

        for scan_path in $scan_paths; do
            [ ! -d "$scan_path" ] && continue
            while IFS= read -r entry; do
                [ -z "$entry" ] && continue
                local links=$(stat -f%l "$entry" 2>/dev/null)
                local size=$(stat -f%z "$entry" 2>/dev/null)
                if [ "${links:-0}" = "65535" ] && [ "${size:-1}" = "0" ]; then
                    stub_count=$((stub_count + 1))
                    local relpath="${entry#$HOME/}"
                    if [ "$stub_count" -le 20 ]; then
                        log ERROR "     Korrupt: ~/${relpath} (links=65535 size=0)"
                    fi
                    if $ICLOUD_STUBS_DELETE; then
                        run_or_dry rm -rf "$entry" 2>/dev/null
                    fi
                fi
            done < <(find "$scan_path" -maxdepth 3 \( -type f -o -type d \) 2>/dev/null)
        done

        if [ "$stub_count" -gt 0 ]; then
            if $ICLOUD_STUBS_DELETE; then
                log FIX "   ${stub_count} korrupte Stubs entfernt"
                report_add FIX "iCloud: ${stub_count} korrupte Stubs entfernt"
                fixes=$((fixes + 1))
            else
                log WARN "   ${stub_count} korrupte Stubs gefunden (ICLOUD_STUBS_DELETE=true zum Loeschen)"
                log INFO "   iCloud: ${stub_count} korrupte Stubs (Config: ICLOUD_STUBS_DELETE)"
                warns=$((warns + 1))
            fi
        else
            log STEP "   Keine korrupten Stubs"
        fi
    else
        log STEP "   [2/6] Stubs-Scan: uebersprungen (Config)"
    fi

    # ── [3/6] bird (iCloud-Daemon) Status ──
    log STEP "   [3/6] bird-Daemon Status..."
    local bird_cpu=$(ps -eo %cpu,comm 2>/dev/null | awk '/\/bird$/ {printf "%d", $1}')
    local bird_mem=$(ps -eo %mem,comm 2>/dev/null | awk '/\/bird$/ {printf "%.1f", $1}')
    local bird_pid=$(pgrep -x bird 2>/dev/null | head -1)

    if [ -n "$bird_pid" ]; then
        log STEP "   bird: PID ${bird_pid}, CPU ${bird_cpu:-0}%, MEM ${bird_mem:-0}%"

        if [ "${bird_cpu:-0}" -gt 50 ]; then
            log WARN "   bird CPU: ${bird_cpu}% (haengt moeglicherweise)"
            if $ICLOUD_RESTART_BIRD; then
                log FIX "   Starte bird neu..."
                run_or_dry killall bird 2>/dev/null
                sleep 3
                # bird wird automatisch von launchd neugestartet
                if pgrep -x bird &>/dev/null; then
                    log FIX "   bird neugestartet"
                    report_add FIX "iCloud: bird neugestartet (CPU war ${bird_cpu}%)"
                    fixes=$((fixes + 1))
                else
                    log WARN "   bird wurde nicht automatisch neugestartet"
                    log INFO "   iCloud: bird nicht neugestartet"
                fi
            else
                log INFO "   iCloud: bird CPU ${bird_cpu}%"
                warns=$((warns + 1))
            fi
        fi
    else
        log WARN "   bird-Daemon nicht aktiv"
        log INFO "   iCloud: bird nicht aktiv"
        warns=$((warns + 1))
    fi

    # ── [4/6] iCloud Drive Speicher ──
    # Fix #139: Timeout fuer du/find auf iCloud (fileproviderd kann haengen)
    log STEP "   [4/6] iCloud Drive Speicher..."
    if [ -d "$icloud_dir" ]; then
        local icloud_size=$(timeout 10 du -sm "$icloud_dir" 2>/dev/null | awk '{print $1}')
        if [ $? -eq 124 ] || [ -z "$icloud_size" ]; then
            icloud_size=0
            log WARN "   iCloud Drive: du timeout (fileproviderd haengt?)"
        fi
        local icloud_files=$(timeout 10 find "$icloud_dir" -type f 2>/dev/null | wc -l)
        icloud_files=${icloud_files##* }
        log STEP "   iCloud Drive: ${icloud_size} MB lokal, ${icloud_files} Dateien"

        # Pruefen auf .icloud-Platzhalter (nicht heruntergeladene Dateien)
        local placeholder_count=$(timeout 10 find "$icloud_dir" -name "*.icloud" -type f 2>/dev/null | wc -l)
        placeholder_count=${placeholder_count##* }
        if [ "${placeholder_count:-0}" -gt 0 ]; then
            log STEP "   ${placeholder_count} Dateien nur in der Cloud (nicht lokal)"
        fi
    else
        log STEP "   iCloud Drive Pfad nicht vorhanden"
    fi

    # ── [5/6] Verwaiste CloudKit-Container ──
    if $ICLOUD_ORPHAN_CONTAINERS_WARN; then
        log STEP "   [5/6] Verwaiste CloudKit-Container..."
        local orphan_containers=0
        local orphan_size_total=0
        local mobile_docs="$HOME/Library/Mobile Documents"
        if [ -d "$mobile_docs" ]; then
            # Batch: Alle Bundle-IDs einmal sammeln (spart ~50 mdfind-Forks)
            local installed_ids_file=$(mktemp)
            timeout 15 mdfind "kMDItemContentType == 'com.apple.application-bundle'" 2>/dev/null | \
                xargs mdls -name kMDItemCFBundleIdentifier 2>/dev/null | \
                awk -F'"' '/kMDItemCFBundleIdentifier/ && $2 != "" {print $2}' | \
                sort -u > "$installed_ids_file"

            while IFS= read -r container; do
                [ -z "$container" ] && continue
                local cname=$(basename "$container")
                # Apple-eigene Container und System-Ordner ueberspringen
                [ "$cname" = "com~apple~CloudDocs" ] && continue
                [[ "$cname" == com~apple~* ]] && continue
                [ "$cname" = ".Trash" ] && continue
                # Container-Bundle-ID rekonstruieren (~ → .)
                local bundle_id=$(echo "$cname" | tr '~' '.')
                # Pruefen gegen gecachte Bundle-ID-Liste (grep statt mdfind)
                if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
                    # Pruefen ob Container Daten enthaelt
                    local container_size=$(timeout 5 du -sm "$container" 2>/dev/null | awk '{print $1}')
                    [ -z "$container_size" ] && container_size=0
                    if [ "$container_size" -gt 0 ]; then
                        orphan_containers=$((orphan_containers + 1))
                        orphan_size_total=$((orphan_size_total + container_size))
                        [ "$orphan_containers" -le 10 ] && log STEP "     Verwaist: ${cname} (${container_size} MB)"
                    fi
                fi
            done < <(find "$mobile_docs" -maxdepth 1 -type d -mindepth 1 2>/dev/null)

            if [ "$orphan_containers" -gt 0 ]; then
                log WARN "   ${orphan_containers} verwaiste CloudKit-Container (~${orphan_size_total} MB)"
                # Fix #145: Always-on Self-Healing - Verwaiste Container immer loeschen (kein Size-Limit)
                if $SELFHEAL_ICLOUD_CONTAINERS && ! $DRY_RUN; then
                    local cleaned_containers=0
                    while IFS= read -r container; do
                        [ -z "$container" ] && continue
                        local cname=$(basename "$container")
                        [ "$cname" = "com~apple~CloudDocs" ] && continue
                        [[ "$cname" == com~apple~* ]] && continue
                        [ "$cname" = ".Trash" ] && continue
                        local bundle_id=$(echo "$cname" | tr '~' '.')
                        if ! grep -qxF "$bundle_id" "$installed_ids_file" 2>/dev/null; then
                            local cs=$(timeout 5 du -sm "$container" 2>/dev/null | awk '{print $1}')
                            if [ "${cs:-0}" -gt 0 ]; then
                                rm -rf "$container" 2>/dev/null && cleaned_containers=$((cleaned_containers + 1))
                                log FIX "     Geloescht: ${cname} (${cs} MB)"
                            fi
                        fi
                    done < <(find "$mobile_docs" -maxdepth 1 -type d -mindepth 1 2>/dev/null)
                    [ "$cleaned_containers" -gt 0 ] && report_add FIX "iCloud: ${cleaned_containers} verwaiste Container geloescht (~${orphan_size_total} MB)"
                else
                    log INFO "   iCloud: ${orphan_containers} verwaiste Container (~${orphan_size_total} MB)"
                fi
                warns=$((warns + 1))
            else
                log STEP "   Keine verwaisten Container"
            fi
            rm -f "$installed_ids_file"
        fi
    else
        log STEP "   [5/6] CloudKit-Container: uebersprungen (Config)"
    fi

    # ── [6/6] Pending Sync + Stuck Downloads ──
    log STEP "   [6/6] Sync-Status..."
    local brctl_avail=false
    command_exists brctl && brctl_avail=true

    if $brctl_avail; then
        # brctl status mit timeout (kann bei vielen Containern >60s dauern)
        local sync_status
        sync_status=$(timeout 15 brctl status 2>/dev/null | head -50)
        # ANSI-Codes aus brctl-Output entfernen (verursachen Zaehl-Fehler)
        local clean_sync=$(echo "$sync_status" | sed $'s/\x1b\\[[0-9;]*m//g')
        local needs_sync_count=$(echo "$clean_sync" | grep -c "needs-sync" 2>/dev/null || echo 0)
        local sync_disabled_count=$(echo "$clean_sync" | grep -c "SYNC DISABLED" 2>/dev/null || echo 0)

        if [ "${needs_sync_count:-0}" -gt 5 ]; then
            log WARN "   ${needs_sync_count} Container warten auf Sync"
            if $ICLOUD_RESTART_BIRD && [ "${needs_sync_count:-0}" -gt 20 ]; then
                log FIX "   Viele wartende Syncs - starte bird neu..."
                run_or_dry killall bird 2>/dev/null
                sleep 3
                report_add FIX "iCloud: bird neugestartet (${needs_sync_count} pending syncs)"
                fixes=$((fixes + 1))
            else
                log INFO "   iCloud: ${needs_sync_count} Container warten auf Sync"
                warns=$((warns + 1))
            fi
        else
            log STEP "   Sync-Status: OK (${needs_sync_count:-0} pending)"
        fi

        if [ "${sync_disabled_count:-0}" -gt 0 ]; then
            log STEP "   ${sync_disabled_count} Container mit deaktiviertem Sync (deinstallierte Apps)"
        fi
    else
        log STEP "   brctl nicht verfuegbar - Sync-Status uebersprungen"
    fi

    # Zusammenfassung
    if [ "$fixes" -gt 0 ]; then
        log FIX "   iCloud: ${fixes} Reparaturen, ${warns} Warnungen"
    elif [ "$warns" -gt 0 ]; then
        log WARN "   iCloud: ${warns} Warnungen"
    else
        log INFO "   iCloud: alles OK"
        report_add SUCCESS "iCloud Sync: gesund"
    fi
}

#############################
# 6e. macOS PERFORMANCE OPTIMIERUNG (Fix #93)
#############################

module_performance() {
    log INFO "macOS Performance Optimierung..."
    local perf_fixes=0
    local perf_warns=0

    # Fix #110: ps-Output einmal cachen statt 5x forken
    local _ps_rss_cache _ps_cpu_cache
    _ps_rss_cache=$(ps -eo rss=,pid=,comm=,uid= 2>/dev/null)
    _ps_cpu_cache=$(ps -eo %cpu=,pid=,comm= 2>/dev/null)

    # ── [1/8] DNS Latenz ──
    log STEP "   [1/8] DNS Latenz..."
    local dns_ms_raw=$(curl -so /dev/null -w "%{time_namelookup}" https://www.apple.com 2>/dev/null)
    local dns_ms_int=$(echo "${dns_ms_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    if [ "${dns_ms_int:-0}" -gt 100 ]; then
        log WARN "   DNS langsam: ${dns_ms_int}ms (>100ms)"
        log INFO "   DNS-Latenz: ${dns_ms_int}ms (transient)"
        perf_warns=$((perf_warns + 1))
    else
        log STEP "   DNS OK: ${dns_ms_int:-?}ms"
    fi

    # ── [2/8] SSD TRIM + SMART ──
    log STEP "   [2/8] SSD TRIM & SMART..."
    local disk_info=$(diskutil info disk0 2>/dev/null)
    local trim_status=$(echo "$disk_info" | awk -F: '/TRIM Support:/ {gsub(/^[ ]+/,"",$2); print $2}')
    if [ -n "$trim_status" ]; then
        if echo "$trim_status" | grep -qi "yes"; then
            log STEP "   TRIM: aktiviert"
        else
            log WARN "   TRIM: DEAKTIVIERT (SSD-Performance leidet!)"
            log INFO "   SSD TRIM deaktiviert"
            perf_warns=$((perf_warns + 1))
        fi
    fi
    local smart_status=$(echo "$disk_info" | awk -F: '/SMART Status:/ {gsub(/^[ ]+/,"",$2); print $2}')
    if [ -n "$smart_status" ]; then
        if echo "$smart_status" | grep -qi "Verified"; then
            log STEP "   SMART: Verified"
        else
            log ERROR "   SMART: $smart_status - DISK PRUEFEN!"
            report_add ERROR "SMART Status: $smart_status"
        fi
    fi
    # APFS Container Health
    local apfs_free=$(diskutil apfs list 2>/dev/null | awk '/Free Space:/ {print $NF; exit}')
    [ -n "$apfs_free" ] && log STEP "   APFS Free: $apfs_free"

    # ── [3/8] Spotlight Exclusions ──
    if $PERF_SPOTLIGHT_EXCLUDE; then
        log STEP "   [3/8] Spotlight Exclusions..."
        local spotlight_excluded=0
        local spotlight_dirs=(
            "$HOME/go/pkg"
            "$HOME/miniforge3"
            "$HOME/Venvs"
            "$HOME/.ollama/models"
            "$HOME/.cargo"
            "$HOME/.rustup"
            "$HOME/.npm"
            "$HOME/.gradle"
            "$HOME/.docker"
        )
        for sdir in "${spotlight_dirs[@]}"; do
            if [ -d "$sdir" ] && [ ! -f "$sdir/.metadata_never_index" ]; then
                run_or_dry touch "$sdir/.metadata_never_index"
                log FIX "   Spotlight: $(basename "$sdir") ausgeschlossen"
                spotlight_excluded=$((spotlight_excluded + 1))
            fi
        done
        [ "$spotlight_excluded" -gt 0 ] && {
            perf_fixes=$((perf_fixes + spotlight_excluded))
            report_add FIX "Spotlight: ${spotlight_excluded} Verzeichnisse ausgeschlossen"
        }
    else
        log STEP "   [3/8] Spotlight Exclusions: uebersprungen (Config)"
    fi

    # ── [4/8] CPU & Thermal ──
    log STEP "   [4/8] CPU & Thermal..."
    local cpu_hogs
    cpu_hogs=$(echo "$_ps_cpu_cache" | sort -rn | awk '$1>50.0 {printf "     PID %s: %s (%.0f%%)\n", $2, $3, $1}' | head -5)
    if [ -n "$cpu_hogs" ]; then
        log INFO "   CPU-Hogs (>50%, transient):"
        echo "$cpu_hogs" | while IFS= read -r line; do
            [ -n "$line" ] && log STEP "$line"
        done
    else
        log STEP "   Keine CPU-Hogs"
    fi
    local cpu_speed_limit=$(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/ {print $3}')
    if [ -n "$cpu_speed_limit" ] && [ "$cpu_speed_limit" -lt 100 ] 2>/dev/null; then
        log WARN "   Thermal Throttling! CPU auf ${cpu_speed_limit}% gedrosselt"
        log INFO "   CPU thermisch gedrosselt (${cpu_speed_limit}%)"
        perf_warns=$((perf_warns + 1))
    else
        log STEP "   Kein Thermal Throttling"
    fi

    # ── [5/8] WindowServer Performance ──
    log STEP "   [5/8] WindowServer..."
    local ws_cpu=$(echo "$_ps_cpu_cache" | awk '/WindowServer/ {print int($1)}')
    if [ "${ws_cpu:-0}" -gt 15 ]; then
        log INFO "   WindowServer: ${ws_cpu}% CPU (transient)"
    else
        log STEP "   WindowServer: ${ws_cpu:-0}% CPU"
    fi

    # ── [6/8] Swap-Analyse ──
    log STEP "   [6/8] Swap-Analyse..."
    local swap_info=$(sysctl -n vm.swapusage 2>/dev/null)
    local swap_used_perf=$(echo "$swap_info" | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="used") print $(i+1)}' | cut -d. -f1)
    local swap_total_perf=$(echo "$swap_info" | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="total") print $(i+1)}' | cut -d. -f1)
    [ -z "$swap_used_perf" ] && swap_used_perf=0
    if [ "$swap_used_perf" -gt 4096 ] 2>/dev/null; then
        log WARN "   Swap: ${swap_used_perf}/${swap_total_perf:-?} MB (hoch!)"
        log STEP "   Empfehlung: Apps schliessen oder RAM aufrüsten"
        log INFO "   Swap hoch: ${swap_used_perf} MB"
        perf_warns=$((perf_warns + 1))
    elif [ "$swap_used_perf" -gt 1024 ] 2>/dev/null; then
        log STEP "   Swap: ${swap_used_perf} MB (moderat)"
    else
        log STEP "   Swap: ${swap_used_perf} MB (niedrig)"
    fi

    # ── [7/8] Unnoetige LaunchAgents deaktivieren ──
    if $PERF_DISABLE_AGENTS; then
        log STEP "   [7/8] LaunchAgents bereinigen..."
        local disabled_agents=0
        for pattern in $PERF_DISABLE_AGENT_PATTERNS; do
            for plist in "$HOME/Library/LaunchAgents/"*"${pattern}"*".plist" ; do
                [ ! -f "$plist" ] && continue
                local agent_label=$(basename "$plist" .plist)
                # Pruefen ob geladen
                if launchctl list "$agent_label" &>/dev/null; then
                    run_or_dry launchctl bootout "gui/$(id -u)" "$plist"
                    log FIX "     LaunchAgent deaktiviert: $agent_label"
                    disabled_agents=$((disabled_agents + 1))
                else
                    log STEP "     Agent bereits inaktiv: $agent_label"
                fi
            done
        done
        [ "$disabled_agents" -gt 0 ] && {
            report_add FIX "LaunchAgents: ${disabled_agents} deaktiviert"
            perf_fixes=$((perf_fixes + 1))
        }
    else
        log STEP "   [7/8] LaunchAgents: uebersprungen (Config)"
    fi

    # ── [8/8] Ollama Model Cleanup ──
    if $PERF_CLEAN_OLLAMA && command_exists ollama; then
        log STEP "   [8/8] Ollama Model Cleanup..."
        local ollama_was_running=false
        ollama_available && ollama_was_running=true

        # Sicherstellen dass Ollama laeuft fuer rm
        if ! $ollama_was_running; then
            ollama serve &>/dev/null &
            sleep 3
        fi

        if ollama_available; then
            local installed_models=$(ollama list 2>/dev/null | awk 'NR>1 {print $1}')
            local removed_models=0
            for model in $installed_models; do
                local keep=false
                for keeper in $OLLAMA_KEEP_MODELS; do
                    if [ "$model" = "$keeper" ]; then
                        keep=true
                        break
                    fi
                done
                if ! $keep; then
                    run_or_dry ollama rm "$model"
                    log FIX "     Ollama-Modell entfernt: $model"
                    removed_models=$((removed_models + 1))
                else
                    log STEP "     Behalten: $model"
                fi
            done
            # Wenn Ollama nur temporaer gestartet, wieder stoppen
            if ! $ollama_was_running; then
                pkill ollama 2>/dev/null
                log STEP "     Ollama-Server wieder gestoppt (RAM freigegeben)"
            fi
            [ "$removed_models" -gt 0 ] && {
                report_add FIX "Ollama: ${removed_models} Modelle entfernt"
                perf_fixes=$((perf_fixes + 1))
                ollama_list_invalidate
            }
        else
            log WARN "   Ollama-Server nicht erreichbar - Cleanup uebersprungen"
        fi
    else
        log STEP "   [8/8] Ollama Cleanup: uebersprungen (Config/nicht installiert)"
    fi

    # ── Zusammenfassung ──
    log INFO "   Performance: ${perf_fixes} Optimierungen, ${perf_warns} Empfehlungen"
    [ "$perf_fixes" -gt 0 ] && report_add FIX "Performance: ${perf_fixes} Optimierungen angewendet"
    [ "$perf_warns" -gt 0 ] && log INFO "   ${perf_warns} Empfehlungen uebersprungen (brauchen sudo/Config)"
    return 0
}

#############################
# 6b. SELF-HEALING PREFLIGHT
#############################

selfheal_preflight() {
    log INFO "Self-Healing Preflight Check..."

    if command_exists brew; then
        log STEP "   Pruefe Homebrew-Zustand..."
        if ! brew --prefix &>/dev/null; then
            log WARN "   Homebrew reagiert nicht"
            log INFO "   Homebrew reagiert nicht (brew --prefix fehlgeschlagen)"
        else
            log STEP "   Homebrew OK"
        fi
    fi

    log STEP "   Pruefe DNS..."
    if ! host google.com &>/dev/null 2>&1; then
        log WARN "   DNS-Aufloesung fehlgeschlagen"
        sudo -n dscacheutil -flushcache 2>/dev/null
        sudo -n killall -HUP mDNSResponder 2>/dev/null
        sleep 1
        if host google.com &>/dev/null 2>&1; then
            log FIX "   DNS nach Flush OK"
            report_add FIX "DNS-Cache geleert (Preflight)"
        fi
    else
        log STEP "   DNS OK"
    fi

    local disk_pct=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [ "$disk_pct" -gt "$DISK_CRITICAL_THRESHOLD" ] 2>/dev/null; then
        log ERROR "   KRITISCH: Disk ${disk_pct}% voll!"
        log WARN "   Raeume Temp-Dateien auf..."
        rm -rf /private/var/tmp/* 2>/dev/null
        rm -rf "$HOME/Library/Caches"/* 2>/dev/null
        report_add FIX "Notfall-Cleanup bei ${disk_pct}% Disk"
    elif [ "$disk_pct" -gt "$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
        log WARN "   Disk ${disk_pct}% belegt (Schwelle: ${DISK_USAGE_THRESHOLD}%)"
    else
        log STEP "   Disk OK (${disk_pct}%)"
    fi

    log INFO "   Preflight abgeschlossen"
}

#############################
# 7. SYSTEM BENCHMARK (Fix #53)
#############################

BENCHMARK_DIR="$MEISTER_DIR/benchmarks"
BENCHMARK_INTERVAL=86400  # 24h in Sekunden
mkdir -p "$BENCHMARK_DIR" 2>/dev/null

benchmark_should_run() {
    local last_file="$BENCHMARK_DIR/last_run"
    [ ! -f "$last_file" ] && return 0
    local last_ts=$(cat "$last_file" 2>/dev/null || echo 0)
    local now=$(date +%s)
    [ $((now - last_ts)) -ge "$BENCHMARK_INTERVAL" ]
}

# Fix #106: date +%s%N funktioniert nicht auf macOS (gibt "N" statt Nanosekunden)
# → perl oder gdate fuer Millisekunden-Praezision
_epoch_ms() {
    if command_exists gdate; then
        gdate +%s%N | cut -c1-13
    elif command_exists perl; then
        perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
    else
        echo "$(date +%s)000"
    fi
}

benchmark_cpu() {
    # Single-Core: Pi-Berechnung via bc (1000 Stellen)
    local start=$(_epoch_ms)
    echo "scale=1000; 4*a(1)" | bc -l > /dev/null 2>&1
    local end=$(_epoch_ms)
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    echo "$ms"
}

benchmark_disk_write() {
    local tmpf="$BENCHMARK_DIR/.disktest_$$"
    local start=$(_epoch_ms)
    dd if=/dev/zero of="$tmpf" bs=1m count=256 2>/dev/null
    sync
    local end=$(_epoch_ms)
    rm -f "$tmpf"
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    local mbps=$(( 256 * 1000 / ms ))
    echo "$mbps"
}

benchmark_disk_read() {
    local tmpf="$BENCHMARK_DIR/.disktest_read_$$"
    dd if=/dev/zero of="$tmpf" bs=1m count=256 2>/dev/null
    sync
    # Fix #118: purge braucht sudo
    sudo -n purge 2>/dev/null || true
    local start=$(_epoch_ms)
    dd if="$tmpf" of=/dev/null bs=1m 2>/dev/null
    local end=$(_epoch_ms)
    rm -f "$tmpf"
    local ms=$(( end - start ))
    [ "$ms" -le 0 ] && ms=1
    local mbps=$(( 256 * 1000 / ms ))
    echo "$mbps"
}

benchmark_network() {
    # Fix #87: Latenz + DNS in EINEM curl-Aufruf statt zwei
    local curl_times
    curl_times=$(curl -so /dev/null -w "%{time_namelookup} %{time_connect}" \
        https://www.apple.com 2>/dev/null || echo "0 0")
    local dns_raw connect_raw
    read -r dns_raw connect_raw <<< "$curl_times"
    local lat_ms=$(echo "${connect_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    local dns_ms=$(echo "${dns_raw:-0} * 1000" | bc 2>/dev/null | cut -d. -f1)
    [ -z "$lat_ms" ] && lat_ms=0
    [ -z "$dns_ms" ] && dns_ms=0

    # Download-Speed: 10MB von Apple CDN
    local dl_speed="0"
    local dl_out
    dl_out=$(curl -so /dev/null -w "%{speed_download}" \
        "https://updates.cdn-apple.com/2019/cert/041-88431-20191011-3d8da658-dca4-4a5b-b67c-69e87e3571b2/InstallAssistant.pkg" \
        --max-time 10 --range 0-10485759 2>/dev/null || echo "0")
    if [ -n "$dl_out" ] && [ "$dl_out" != "0" ]; then
        dl_speed=$(echo "$dl_out / 1048576" | bc -l 2>/dev/null | cut -c1-5)
    fi
    [ -z "$dl_speed" ] && dl_speed="0"

    echo "${lat_ms} ${dns_ms} ${dl_speed}"
}

benchmark_memory() {
    local total_mb free_mb pressure swap_used_mb
    total_mb=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1048576}')
    # Fix #87: vm_stat EINMAL aufrufen, beide Werte in einem awk extrahieren
    local pagesize=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
    local free_pages inactive_pages
    read -r free_pages inactive_pages <<< $(vm_stat 2>/dev/null | awk '
        /Pages free:/ {gsub(/\./,"",$3); f=$3}
        /Pages inactive:/ {gsub(/\./,"",$3); i=$3}
        END {print f+0, i+0}')
    free_mb=$(( (${free_pages:-0} + ${inactive_pages:-0}) * pagesize / 1048576 ))
    # Memory Pressure (1=normal, 2=warn, 4=critical)
    pressure=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "0")
    swap_used_mb=$(LC_ALL=C sysctl -n vm.swapusage 2>/dev/null | awk -F'[ =M]+' '{for(i=1;i<=NF;i++) if($i=="used") {gsub(/,/,".",$((i+1))); printf "%d", $(i+1)}}')
    [ -z "$swap_used_mb" ] && swap_used_mb=0

    echo "${total_mb} ${free_mb} ${pressure} ${swap_used_mb}"
}

benchmark_security() {
    local filevault firewall gatekeeper sip xprotect
    # FileVault
    if fdesetup status 2>/dev/null | grep -q "On"; then
        filevault="ON"
    else
        filevault="OFF"
    fi
    # Firewall
    local fw_state
    fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo "")
    if echo "$fw_state" | grep -qi "enabled"; then
        firewall="ON"
    else
        firewall="OFF"
    fi
    # Gatekeeper
    if spctl --status 2>/dev/null | grep -q "enabled"; then
        gatekeeper="ON"
    else
        gatekeeper="OFF"
    fi
    # SIP (System Integrity Protection)
    if csrutil status 2>/dev/null | grep -q "enabled"; then
        sip="ON"
    else
        sip="OFF"
    fi
    # Fix #88: XProtect Version via pkgutil statt system_profiler (~10s schneller)
    xprotect=$(pkgutil --pkg-info com.apple.pkg.XProtectPlistConfigData 2>/dev/null | awk '/version:/ {print $2}')
    [ -z "$xprotect" ] && xprotect=$(pkgutil --pkg-info com.apple.pkg.XProtectPayloads 2>/dev/null | awk '/version:/ {print $2}')
    [ -z "$xprotect" ] && xprotect="n/a"

    echo "${filevault} ${firewall} ${gatekeeper} ${sip} ${xprotect}"
}

benchmark_system_info() {
    local uptime_secs load1 load5 load15 thermal battery_pct battery_cycles battery_health
    # Uptime
    uptime_secs=$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,=]+' '{for(i=1;i<=NF;i++) if($i=="sec") print $(i+1)}')
    if [ -n "$uptime_secs" ]; then
        local now=$(date +%s)
        uptime_secs=$((now - uptime_secs))
    else
        uptime_secs=0
    fi
    local uptime_days=$((uptime_secs / 86400))

    # Load Average
    read -r load1 load5 load15 <<< $(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}')
    [ -z "$load1" ] && load1="0" && load5="0" && load15="0"

    # Thermal (macOS Sequoia+)
    thermal=$(pmset -g therm 2>/dev/null | awk '/CPU_Speed_Limit/ {print $3}' || echo "100")
    [ -z "$thermal" ] && thermal="100"

    # Battery (nur MacBooks)
    battery_pct=""
    battery_cycles=""
    battery_health=""
    if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
        battery_pct=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')
        # Fix #87: ioreg EINMAL aufrufen statt dreimal (~3s gespart)
        local ioreg_cache
        ioreg_cache=$(ioreg -rc AppleSmartBattery 2>/dev/null)
        # Fix: Nur Top-Level-Keys matchen (^ + Leerzeichen + "), nicht innerhalb BatteryData-Blob
        battery_cycles=$(echo "$ioreg_cache" | awk '/^[[:space:]]+"CycleCount" =/ {print $NF}')
        battery_health=$(echo "$ioreg_cache" | awk -F'"' '/^[[:space:]]+"BatteryHealth" =/ {print $4}')
        [ -z "$battery_health" ] && battery_health=$(echo "$ioreg_cache" | awk '/^[[:space:]]+"MaxCapacity" =/ {print $NF}')
    fi
    [ -z "$battery_pct" ] && battery_pct="-"
    [ -z "$battery_cycles" ] && battery_cycles="-"
    [ -z "$battery_health" ] && battery_health="-"

    echo "${uptime_days} ${load1} ${load5} ${load15} ${thermal} ${battery_pct} ${battery_cycles} ${battery_health}"
}

benchmark_save_json() {
    local ts="$1" cpu_ms="$2" disk_w="$3" disk_r="$4"
    local net_lat="$5" net_dns="$6" net_dl="$7"
    local mem_total="$8" mem_free="$9" mem_pressure="${10}" swap_mb="${11}"
    local fv="${12}" fw="${13}" gk="${14}" sip_val="${15}" xp="${16}"
    local up_days="${17}" l1="${18}" l5="${19}" l15="${20}" therm="${21}"
    local batt_pct="${22}" batt_cyc="${23}" batt_hp="${24}"
    local date_str=$(date +%Y-%m-%d)
    local json_file="$BENCHMARK_DIR/${date_str}.json"

    if command_exists jq; then
        jq -n \
            --arg ts "$ts" \
            --argjson cpu "$cpu_ms" \
            --argjson disk_w "$disk_w" \
            --argjson disk_r "$disk_r" \
            --argjson net_lat "$net_lat" \
            --argjson net_dns "$net_dns" \
            --arg net_dl "$net_dl" \
            --argjson mem_total "$mem_total" \
            --argjson mem_free "$mem_free" \
            --argjson mem_pressure "$mem_pressure" \
            --argjson swap "$swap_mb" \
            --arg filevault "$fv" \
            --arg firewall "$fw" \
            --arg gatekeeper "$gk" \
            --arg sip "$sip_val" \
            --arg xprotect "$xp" \
            --argjson uptime_days "$up_days" \
            --arg load1 "$l1" \
            --arg load5 "$l5" \
            --arg load15 "$l15" \
            --arg thermal "$therm" \
            --arg battery_pct "$batt_pct" \
            --arg battery_cycles "$batt_cyc" \
            --arg battery_health "$batt_hp" \
            '{timestamp:$ts, cpu_ms:$cpu, disk_write_mbps:$disk_w, disk_read_mbps:$disk_r,
              net_latency_ms:$net_lat, net_dns_ms:$net_dns, net_download_mbps:$net_dl,
              mem_total_mb:$mem_total, mem_free_mb:$mem_free, mem_pressure:$mem_pressure, swap_mb:$swap,
              security:{filevault:$filevault, firewall:$firewall, gatekeeper:$gatekeeper, sip:$sip, xprotect:$xprotect},
              uptime_days:$uptime_days, load:{l1:$load1, l5:$load5, l15:$load15},
              thermal:$thermal, battery:{pct:$battery_pct, cycles:$battery_cycles, health:$battery_health}}' \
            > "$json_file"
    else
        cat > "$json_file" << JSONEOF
{"timestamp":"$ts","cpu_ms":$cpu_ms,"disk_write_mbps":$disk_w,"disk_read_mbps":$disk_r,"net_latency_ms":$net_lat,"net_dns_ms":$net_dns,"net_download_mbps":"$net_dl","mem_total_mb":$mem_total,"mem_free_mb":$mem_free,"mem_pressure":$mem_pressure,"swap_mb":$swap_mb,"security":{"filevault":"$fv","firewall":"$fw","gatekeeper":"$gk","sip":"$sip_val","xprotect":"$xp"},"uptime_days":$up_days,"load":{"l1":"$l1","l5":"$l5","l15":"$l15"},"thermal":"$therm","battery":{"pct":"$batt_pct","cycles":"$batt_cyc","health":"$batt_hp"}}
JSONEOF
    fi
    echo "$json_file"
}

benchmark_compare() {
    local current_file="$1"
    # Letzten vorherigen Benchmark finden
    local prev_file
    prev_file=$(ls -1t "$BENCHMARK_DIR"/*.json 2>/dev/null | grep -v "$(basename "$current_file")" | head -1)
    [ -z "$prev_file" ] && { log STEP "   Erster Benchmark - kein Vergleich moeglich"; return; }

    if ! command_exists jq; then return; fi

    local prev_cpu=$(jq -r '.cpu_ms' "$prev_file" 2>/dev/null || echo 0)
    local curr_cpu=$(jq -r '.cpu_ms' "$current_file" 2>/dev/null || echo 0)
    local prev_dw=$(jq -r '.disk_write_mbps' "$prev_file" 2>/dev/null || echo 0)
    local curr_dw=$(jq -r '.disk_write_mbps' "$current_file" 2>/dev/null || echo 0)
    local prev_date=$(jq -r '.timestamp' "$prev_file" 2>/dev/null | cut -d' ' -f1)

    log STEP "   Vergleich mit $prev_date:"

    # CPU: niedriger = besser
    if [ "$prev_cpu" -gt 0 ] && [ "$curr_cpu" -gt 0 ]; then
        local cpu_diff=$(( (curr_cpu - prev_cpu) * 100 / prev_cpu ))
        if [ "$cpu_diff" -gt 20 ]; then
            log WARN "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (+${cpu_diff}% langsamer!)"
            log INFO "   CPU-Benchmark ${cpu_diff}% langsamer als letzter Lauf"
        elif [ "$cpu_diff" -lt -10 ]; then
            log INFO "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (${cpu_diff}% schneller)"
        else
            log STEP "   CPU: ${curr_cpu}ms vs ${prev_cpu}ms (stabil)"
        fi
    fi

    # Disk Write: hoeher = besser
    if [ "$prev_dw" -gt 0 ] && [ "$curr_dw" -gt 0 ]; then
        local dw_diff=$(( (curr_dw - prev_dw) * 100 / prev_dw ))
        if [ "$dw_diff" -lt -30 ]; then
            log WARN "   Disk Write: ${curr_dw} MB/s vs ${prev_dw} MB/s (${dw_diff}% langsamer!)"
            log INFO "   Disk-Write ${dw_diff}% langsamer als letzter Lauf"
        else
            log STEP "   Disk Write: ${curr_dw} MB/s vs ${prev_dw} MB/s"
        fi
    fi
}

module_benchmark() {
    if ! benchmark_should_run; then
        log INFO "Benchmark: Bereits heute gelaufen - ueberspringe"
        log STEP "   Naechster Benchmark in ~$((BENCHMARK_INTERVAL - ($(date +%s) - $(cat "$BENCHMARK_DIR/last_run" 2>/dev/null || echo 0)))) Sekunden"
        report_add SUCCESS "Benchmark: skip (bereits heute)"
        return
    fi

    log INFO "System-Benchmark & Security-Audit..."
    local ts=$(date +'%Y-%m-%d %H:%M:%S')

    # 1. CPU Benchmark
    log STEP "   CPU-Benchmark (Pi 1000 Stellen)..."
    local cpu_ms=$(benchmark_cpu)
    log STEP "   CPU: ${cpu_ms}ms"

    # 2. Disk I/O
    log STEP "   Disk-I/O Benchmark (256MB)..."
    local disk_w=$(benchmark_disk_write)
    local disk_r=$(benchmark_disk_read)
    log STEP "   Disk: Write ${disk_w} MB/s, Read ${disk_r} MB/s"

    # 3. Netzwerk
    log STEP "   Netzwerk-Benchmark..."
    local net_lat net_dns net_dl
    read -r net_lat net_dns net_dl <<< $(benchmark_network)
    log STEP "   Netz: Latenz ${net_lat}ms, DNS ${net_dns}ms, Download ${net_dl} MB/s"

    # 4. Memory
    log STEP "   Memory-Status..."
    local mem_total mem_free mem_pressure swap_mb
    read -r mem_total mem_free mem_pressure swap_mb <<< $(benchmark_memory)
    local mem_used=$((mem_total - mem_free))
    local mem_pct=$((mem_used * 100 / mem_total))
    local pressure_txt="normal"
    [ "$mem_pressure" -ge 2 ] 2>/dev/null && pressure_txt="WARNUNG"
    [ "$mem_pressure" -ge 4 ] 2>/dev/null && pressure_txt="KRITISCH"
    log STEP "   RAM: ${mem_used}/${mem_total} MB (${mem_pct}%), Pressure: ${pressure_txt}, Swap: ${swap_mb} MB"

    if [ "$mem_pressure" -ge 2 ] 2>/dev/null; then
        log INFO "   Memory Pressure: ${pressure_txt} (Swap: ${swap_mb} MB)"
    fi
    if [ "$swap_mb" -gt 4096 ] 2>/dev/null; then
        log INFO "   Hoher Swap: ${swap_mb} MB"
    fi

    # 5. Security Audit
    log STEP "   Security-Audit..."
    local fv fw gk sip_status xp
    read -r fv fw gk sip_status xp <<< $(benchmark_security)
    log STEP "   FileVault: $fv | Firewall: $fw | Gatekeeper: $gk | SIP: $sip_status"
    log STEP "   XProtect: $xp"

    # Security Self-Healing: auto-fixen was moeglich
    if [ "$fw" = "OFF" ] && ! $DRY_RUN; then
        sudo -n /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null && \
            { log FIX "   Firewall aktiviert"; report_add FIX "Firewall aktiviert"; fw="ON"; } || \
            log INFO "   Firewall deaktiviert (sudo noetig)"
    fi
    if [ "$gk" = "OFF" ] && ! $DRY_RUN; then
        sudo -n spctl --master-enable 2>/dev/null && \
            { log FIX "   Gatekeeper aktiviert"; report_add FIX "Gatekeeper reaktiviert"; gk="ON"; } || \
            log INFO "   Gatekeeper deaktiviert (sudo noetig)"
    fi
    [ "$fv" = "OFF" ] && log INFO "   FileVault deaktiviert (manuell via Systemeinstellungen)"
    [ "$sip_status" = "OFF" ] && log INFO "   SIP deaktiviert (Recovery Mode noetig)"

    # 6. System-Info
    log STEP "   System-Info..."
    local up_days l1 l5 l15 therm batt_pct batt_cyc batt_hp
    read -r up_days l1 l5 l15 therm batt_pct batt_cyc batt_hp <<< $(benchmark_system_info)
    log STEP "   Uptime: ${up_days} Tage | Load: ${l1}/${l5}/${l15} | Thermal: ${therm}%"
    if [ "$batt_pct" != "-" ]; then
        log STEP "   Batterie: ${batt_pct}% | Zyklen: ${batt_cyc} | Health: ${batt_hp}"
        if [ "$batt_pct" -lt 20 ] 2>/dev/null; then
            log INFO "   Batterie niedrig: ${batt_pct}%"
        fi
    fi

    if [ "$up_days" -gt 30 ] 2>/dev/null; then
        log WARN "   System laeuft seit ${up_days} Tagen - Neustart empfohlen"
        log INFO "   Uptime ${up_days} Tage"
    fi

    # 7. Ergebnisse speichern (JSON)
    local json_file
    json_file=$(benchmark_save_json "$ts" "$cpu_ms" "$disk_w" "$disk_r" \
        "$net_lat" "$net_dns" "$net_dl" \
        "$mem_total" "$mem_free" "$mem_pressure" "$swap_mb" \
        "$fv" "$fw" "$gk" "$sip_status" "$xp" \
        "$up_days" "$l1" "$l5" "$l15" "$therm" \
        "$batt_pct" "$batt_cyc" "$batt_hp")
    log STEP "   Gespeichert: $json_file"

    # 8. Vergleich mit letztem Lauf
    benchmark_compare "$json_file"

    # 9. Timestamp speichern
    date +%s > "$BENCHMARK_DIR/last_run"

    # 10. Alte Benchmarks aufraumen (>90 Tage)
    find "$BENCHMARK_DIR" -name "*.json" -mtime +90 -delete 2>/dev/null

    report_add SUCCESS "Benchmark: CPU ${cpu_ms}ms, Disk W:${disk_w}/R:${disk_r} MB/s, Net ${net_dl} MB/s"
    local sec_ok=0
    [ "$fv" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$fw" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$gk" = "ON" ] && sec_ok=$((sec_ok + 1))
    [ "$sip_status" = "ON" ] && sec_ok=$((sec_ok + 1))
    report_add SUCCESS "Security: ${sec_ok}/4 (FV:$fv FW:$fw GK:$gk SIP:$sip_status)"
}

#############################
# 8. MAIN
#############################

keep_sudo() {
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

# Fix #16: Run-History
save_history() {
    local history_file="$MEISTER_DIR/history.log"
    local end_ts=$(date +%s)
    local total_secs=$((end_ts - SCRIPT_START_TIME))
    local total_mins=$((total_secs / 60))
    local total_secs_rem=$((total_secs % 60))
    local ts=$(date +'%Y-%m-%d %H:%M:%S')
    echo "$ts | ${total_mins}m${total_secs_rem}s | OK:${#REPORT_SUCCESS[@]} FIX:${#REPORT_FIXED[@]} WARN:${#REPORT_WARNINGS[@]} ERR:${#REPORT_ERRORS[@]}" >> "$history_file"
}

print_report() {
    local end_ts=$(date +%s)
    local total_secs=$((end_ts - SCRIPT_START_TIME))
    local total_mins=$((total_secs / 60))
    local total_secs_rem=$((total_secs % 60))

    echo ""
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BLUE}   MEISTER REPORT (v0.09)${NC}"
    echo -e "${BLUE}   Laufzeit: ${total_mins}m ${total_secs_rem}s${NC}"
    $DRY_RUN && echo -e "${YELLOW}   [DRY-RUN MODUS]${NC}"
    echo -e "${BLUE}====================================================${NC}"

    if [ ${#REPORT_SUCCESS[@]} -gt 0 ]; then
        echo -e "\n${GREEN}SUCCESS (${#REPORT_SUCCESS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_SUCCESS[@]}"
    fi
    if [ ${#REPORT_FIXED[@]} -gt 0 ]; then
        echo -e "\n${CYAN}FIXED (${#REPORT_FIXED[@]}):${NC}"
        printf '  - %s\n' "${REPORT_FIXED[@]}"
    fi
    if [ ${#REPORT_WARNINGS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}WARNINGS (${#REPORT_WARNINGS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_WARNINGS[@]}"
    fi
    if [ ${#REPORT_ERRORS[@]} -gt 0 ]; then
        echo -e "\n${RED}ERRORS (${#REPORT_ERRORS[@]}):${NC}"
        printf '  - %s\n' "${REPORT_ERRORS[@]}"
    fi

    # Fix #80: Gesamt-Speicher-Summary aus FIXED-Eintraegen extrahieren
    local total_mb_freed=0
    for entry in "${REPORT_FIXED[@]}"; do
        local mb_val
        mb_val=$(echo "$entry" | grep -oE '[0-9]+ MB' | head -1 | awk '{print $1}')
        [ -n "$mb_val" ] && total_mb_freed=$((total_mb_freed + mb_val))
    done
    if [ "$total_mb_freed" -gt 0 ]; then
        echo -e "\n${GREEN}--- Speicher-Summary ---${NC}"
        if [ "$total_mb_freed" -gt 1024 ]; then
            local gb_freed=$(echo "scale=1; $total_mb_freed / 1024" | bc 2>/dev/null || echo "$((total_mb_freed / 1024))")
            echo "  Freigegeben: ~${gb_freed} GB (${total_mb_freed} MB)"
        else
            echo "  Freigegeben: ~${total_mb_freed} MB"
        fi
    fi

    echo -e "\n${BLUE}====================================================${NC}"
    echo "Log: $LOGFILE"
    echo "Config: $MEISTER_CONFIG"
}

health_dashboard() {
    echo -e "\n${MAGENTA}═══════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Self-Healing Status (v0.09)${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
    if ollama_available; then
        echo -e "  Ollama:  ${GREEN}online${NC} ($OLLAMA_MODEL)"
        local model_count=$(( $(ollama_list_cached | awk 'NR>1' | wc -l) ))
        echo -e "  Modelle: ${model_count}"
    else
        echo -e "  Ollama:  ${RED}offline${NC}"
    fi
    echo -e "  Disk:    $(df -h / | awk 'NR==2 {print $5}') belegt ($(df -h / | awk 'NR==2 {print $4}') frei)"
    local pc=$(( $(ls -1 "$MEISTER_DIR/patches/" 2>/dev/null | wc -l) ))
    echo -e "  Patches: ${pc} gespeichert"
    if [ $pc -gt 0 ]; then
        echo -e "  Letzte:"
        ls -1t "$MEISTER_DIR/patches/" 2>/dev/null | head -5 | while IFS= read -r f; do
            echo -e "    - $f"
        done
    fi
    # Run History
    local history_file="$MEISTER_DIR/history.log"
    if [ -f "$history_file" ]; then
        local run_count=$(wc -l < "$history_file" | xargs)
        echo -e "  Runs:    ${run_count} gesamt"
        echo -e "  Letzte Laeufe:"
        tail -5 "$history_file" | while IFS= read -r line; do
            echo -e "    $line"
        done
    fi
    echo -e "  Config:  $MEISTER_CONFIG"
    # Letzter Benchmark
    local last_bench=$(ls -1t "$BENCHMARK_DIR"/*.json 2>/dev/null | head -1)
    if [ -n "$last_bench" ] && command_exists jq; then
        local b_date=$(basename "$last_bench" .json)
        local b_cpu=$(jq -r '.cpu_ms' "$last_bench" 2>/dev/null)
        local b_dw=$(jq -r '.disk_write_mbps' "$last_bench" 2>/dev/null)
        local b_dr=$(jq -r '.disk_read_mbps' "$last_bench" 2>/dev/null)
        local b_fv=$(jq -r '.security.filevault' "$last_bench" 2>/dev/null)
        local b_fw=$(jq -r '.security.firewall' "$last_bench" 2>/dev/null)
        local b_gk=$(jq -r '.security.gatekeeper' "$last_bench" 2>/dev/null)
        local b_sip=$(jq -r '.security.sip' "$last_bench" 2>/dev/null)
        echo -e "  ─── Benchmark ($b_date) ───"
        echo -e "  CPU:     ${b_cpu}ms | Disk: W:${b_dw}/R:${b_dr} MB/s"
        echo -e "  Security: FV:$b_fv FW:$b_fw GK:$b_gk SIP:$b_sip"
        local bench_count=$(( $(ls -1 "$BENCHMARK_DIR"/*.json 2>/dev/null | wc -l) ))
        echo -e "  History: ${bench_count} Benchmarks gespeichert"
    fi
    echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
}

#############################
# 8. LOG-ANALYSE (Fix #27)
#############################

log_analysis() {
    local history_file="$MEISTER_DIR/history.log"
    [ ! -f "$history_file" ] && return
    local run_count=$(wc -l < "$history_file" | xargs)
    [ "$run_count" -lt 3 ] && return

    log INFO "Log-Analyse: Pruefe wiederkehrende Probleme..."

    # Warnings und Errors aus letzten 5 Runs zaehlen
    local recent_warns=""
    if [ -f "$LOGFILE" ]; then
        recent_warns=$(grep -E "^.* - (WARN|ERROR) - " "$LOGFILE" 2>/dev/null | \
            sed 's/^.* - \(WARN\|ERROR\) - //' | sort | uniq -c | sort -rn | head -10)
    fi

    # Auch .old Log einbeziehen
    if [ -f "${LOGFILE}.old" ]; then
        local old_warns=$(grep -E "^.* - (WARN|ERROR) - " "${LOGFILE}.old" 2>/dev/null | \
            sed 's/^.* - \(WARN\|ERROR\) - //' | sort | uniq -c | sort -rn | head -10)
        if [ -n "$old_warns" ]; then
            recent_warns=$(echo -e "${recent_warns}\n${old_warns}" | sort -rn | head -10)
        fi
    fi

    if [ -n "$recent_warns" ]; then
        # Stale Eintraege rausfiltern (deinstallierte Apps, alte Timeouts)
        local recurring=$(echo "$recent_warns" | awk '$1 >= 3 {$1=""; print}' | sed 's/^ //' | \
            grep -vE "VERWAIST:.*nicht mehr installiert|TIMEOUT bei git remote|Wiederkehrende Probleme")
        if [ -n "$recurring" ]; then
            log INFO "   Wiederkehrende Probleme:"
            echo "$recurring" | while IFS= read -r line; do
                [ -n "$line" ] && log STEP "     - $line"
            done
        else
            log STEP "   Keine wiederkehrenden Probleme (stale Eintraege gefiltert)"
        fi
    fi
}

#############################
# 9. NOTIFICATIONS (Fix #28, #29)
#############################

# Fix #28: terminal-notifier mit Fallback
send_notification() {
    local title="$1"
    local message="$2"
    local subtitle="${3:-}"

    if command_exists terminal-notifier; then
        local tn_args=(-title "$title" -message "$message" -group "meister")
        [ -n "$subtitle" ] && tn_args+=(-subtitle "$subtitle")
        # Clickable: oeffnet Logfile
        tn_args+=(-open "file://$LOGFILE")
        terminal-notifier "${tn_args[@]}" 2>/dev/null
    else
        local osa_msg="$message"
        [ -n "$subtitle" ] && osa_msg="$subtitle: $message"
        osascript -e "display notification \"$osa_msg\" with title \"$title\"" 2>/dev/null
    fi
}

build_report_summary() {
    local summary="OK:${#REPORT_SUCCESS[@]} FIX:${#REPORT_FIXED[@]} WARN:${#REPORT_WARNINGS[@]} ERR:${#REPORT_ERRORS[@]}"
    local end_ts=$(date +%s)
    local total_mins=$(( (end_ts - SCRIPT_START_TIME) / 60 ))
    echo "Meister v0.09 | ${total_mins}min | $summary"
}

send_report_notification() {
    local summary=$(build_report_summary)
    local err_count=${#REPORT_ERRORS[@]}
    local fix_count=${#REPORT_FIXED[@]}

    local subtitle=""
    [ $err_count -gt 0 ] && subtitle="${err_count} Fehler!"
    [ $fix_count -gt 0 ] && subtitle="${subtitle} ${fix_count} Fixes"
    send_notification "Meister" "$summary" "$subtitle"
}

#############################
# 10. LAUNCHAGENT (Fix #30)
#############################

install_launchagent() {
    local script_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    local plist_path="$HOME/Library/LaunchAgents/com.meister.maintenance.plist"
    local label="com.meister.maintenance"

    # Schedule bestimmen
    local interval_secs=604800  # default: weekly
    case "$LAUNCHAGENT_SCHEDULE" in
        daily)   interval_secs=86400 ;;
        weekly)  interval_secs=604800 ;;
    esac

    log INFO "Installiere LaunchAgent ($LAUNCHAGENT_SCHEDULE)..."
    log STEP "   Script: $script_path"
    log STEP "   Plist:  $plist_path"

    # Bestehenden Agent stoppen
    if launchctl list 2>/dev/null | grep -q "$label"; then
        launchctl unload "$plist_path" 2>/dev/null
        log STEP "   Bestehender Agent gestoppt"
    fi

    mkdir -p "$HOME/Library/LaunchAgents"

    # Schedule-Key generieren
    local schedule_key=""
    if [ "$LAUNCHAGENT_SCHEDULE" = "monthly" ]; then
        schedule_key="<key>StartCalendarInterval</key>
    <dict><key>Day</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>"
    else
        schedule_key="<key>StartInterval</key>
    <integer>${interval_secs}</integer>"
    fi

    cat > "$plist_path" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${script_path}</string>
    </array>
    ${schedule_key}
    <key>StandardOutPath</key>
    <string>${MEISTER_DIR}/launchagent.log</string>
    <key>StandardErrorPath</key>
    <string>${MEISTER_DIR}/launchagent_err.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLISTEOF

    launchctl load "$plist_path" 2>/dev/null
    if launchctl list 2>/dev/null | grep -q "$label"; then
        log FIX "LaunchAgent installiert und geladen"
        log INFO "   Schedule: $LAUNCHAGENT_SCHEDULE"
        log INFO "   Deinstallieren: launchctl unload $plist_path && rm $plist_path"
        echo ""
        echo -e "${GREEN}LaunchAgent erfolgreich installiert!${NC}"
        echo -e "  Schedule:      $LAUNCHAGENT_SCHEDULE"
        echo -e "  Plist:         $plist_path"
        echo -e "  Log:           $MEISTER_DIR/launchagent.log"
        echo -e "  Deinstallieren: launchctl unload $plist_path"
    else
        log ERROR "LaunchAgent konnte nicht geladen werden"
        echo -e "${RED}LaunchAgent Installation fehlgeschlagen!${NC}"
    fi
}

# Fix #117: Long-Options vor getopts abfangen (getopts kann nur Short-Options)
for arg in "$@"; do
    case "$arg" in
        --help)    set -- "-h"; break ;;
        --version) echo "meister v0.09"; exit 0 ;;
        --dry-run) set -- "-n"; break ;;
        --*)       echo "[ERROR] Unbekannte Option: $arg (siehe meister -h)"; exit 1 ;;
    esac
done

# ── Args ──
while getopts ":aAXTSCLhcHnIPGq" opt; do
  case $opt in
    a) CLEAN_XCODE=true; EMPTY_TRASH=true
       RUN_SUDO_TASKS=true; CLEAN_CACHES=true; LIST_LARGE_FILES=true; RUN_PERF_TUNE=true; RUN_GIT_REPOS=true ;;
    G) RUN_GIT_REPOS=true ;;
    P) RUN_PERF_TUNE=true ;;
    A) log WARN "ClamAV entfernt - XProtect laeuft in Security Suite" ;;
    X) CLEAN_XCODE=true ;;
    T) EMPTY_TRASH=true ;;
    S) RUN_SUDO_TASKS=true ;;
    C) CLEAN_CACHES=true ;;
    L) LIST_LARGE_FILES=true ;;
    c) log WARN "ClamAV entfernt - XProtect laeuft in Security Suite" ;;
    H) SHOW_HEALTH=true ;;
    n) DRY_RUN=true ;;
    q) QUIET_MODE=true ;;
    I) INSTALL_LAUNCHAGENT=true ;;
    h) cat << 'HELPEOF'
Meister - macOS Wartung & Self-Healing

VERWENDUNG:
  meister              Auto-Detect (Default)
  meister -a           Alle Module erzwingen
  meister -n           Dry-Run
  meister -q           Quiet (nur Warns/Errors/Fixes)
  meister -H           Health Dashboard
  meister -I           LaunchAgent installieren

OVERRIDES:  -X Xcode  -T Trash  -S Sudo  -C Caches
            -L Grosse Dateien  -P Performance  -G Git

Config: ~/.meister/config
HELPEOF
       exit 0 ;;
    \?) log ERROR "Unbekannte Option: -$OPTARG"; exit 1 ;;
  esac
done

MANUAL_FLAGS_SET=false
$CLEAN_XCODE && MANUAL_FLAGS_SET=true
$EMPTY_TRASH && MANUAL_FLAGS_SET=true
$RUN_SUDO_TASKS && MANUAL_FLAGS_SET=true
$CLEAN_CACHES && MANUAL_FLAGS_SET=true
$LIST_LARGE_FILES && MANUAL_FLAGS_SET=true
$RUN_PERF_TUNE && MANUAL_FLAGS_SET=true
$RUN_GIT_REPOS && MANUAL_FLAGS_SET=true

auto_detect() {
    log INFO "Auto-Detect: Analysiere System..."
    local detected=0

    # 1. Xcode DerivedData
    local xcpath="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$xcpath" ]; then
        local xc_mb=$(du -sm "$xcpath" 2>/dev/null | awk '{print $1}')
        xc_mb=${xc_mb:-0}
        if [ "$xc_mb" -ge "$AUTO_XCODE_THRESHOLD_MB" ]; then
            CLEAN_XCODE=true
            detected=$((detected + 1))
            log STEP "   Xcode DerivedData: ${xc_mb}MB (>= ${AUTO_XCODE_THRESHOLD_MB}MB) → aktiviert"
        else
            log STEP "   Xcode DerivedData: ${xc_mb}MB (< ${AUTO_XCODE_THRESHOLD_MB}MB) → OK"
        fi
    fi

    # 2. Papierkorb
    if [ -d "$HOME/.Trash" ]; then
        local trash_items=$(( $(ls -1A "$HOME/.Trash" 2>/dev/null | wc -l) ))
        local trash_mb=$(du -sm "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
        trash_mb=${trash_mb:-0}
        if [ "$trash_items" -ge "$AUTO_TRASH_THRESHOLD_ITEMS" ] || [ "$trash_mb" -ge "$AUTO_TRASH_THRESHOLD_MB" ]; then
            EMPTY_TRASH=true
            detected=$((detected + 1))
            log STEP "   Papierkorb: ${trash_items} Elemente, ${trash_mb}MB → aktiviert"
        else
            log STEP "   Papierkorb: ${trash_items} Elemente, ${trash_mb}MB → OK"
        fi
    fi

    # 3. User Caches
    if [ -d "$HOME/Library/Caches" ]; then
        local cache_mb=$(du -sm "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
        cache_mb=${cache_mb:-0}
        if [ "$cache_mb" -ge "$AUTO_CACHE_THRESHOLD_MB" ]; then
            CLEAN_CACHES=true
            detected=$((detected + 1))
            log STEP "   User Caches: ${cache_mb}MB (>= ${AUTO_CACHE_THRESHOLD_MB}MB) → aktiviert"
        else
            log STEP "   User Caches: ${cache_mb}MB (< ${AUTO_CACHE_THRESHOLD_MB}MB) → OK"
        fi
    fi

    # 4. Disk Usage → grosse Dateien listen
    local disk_usage=$(df -H / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    disk_usage=${disk_usage:-0}
    if [ "$disk_usage" -ge "$DISK_USAGE_THRESHOLD" ]; then
        LIST_LARGE_FILES=true
        detected=$((detected + 1))
        log STEP "   Disk: ${disk_usage}% belegt (>= ${DISK_USAGE_THRESHOLD}%) → grosse Dateien listen"
    else
        log STEP "   Disk: ${disk_usage}% belegt → OK"
    fi

    # 5. periodic scripts (sudo tasks)
    local daily_log="/var/log/daily.out"
    if [ -f "$daily_log" ]; then
        local daily_age_days=$(( ( $(date +%s) - $(stat -f %m "$daily_log" 2>/dev/null || echo 0) ) / 86400 ))
        if [ "$daily_age_days" -ge "$AUTO_PERIODIC_INTERVAL_DAYS" ]; then
            RUN_SUDO_TASKS=true
            detected=$((detected + 1))
            log STEP "   periodic scripts: ${daily_age_days} Tage alt (>= ${AUTO_PERIODIC_INTERVAL_DAYS}) → aktiviert"
        else
            log STEP "   periodic scripts: ${daily_age_days} Tage alt → OK"
        fi
    else
        # Kein Log → wahrscheinlich noch nie gelaufen
        RUN_SUDO_TASKS=true
        detected=$((detected + 1))
        log STEP "   periodic scripts: kein Log gefunden → aktiviert"
    fi

    # 7. Performance + Git (bestehende Auto-Logik beibehalten)
    if $SELFHEAL_PERF_AUTO; then
        RUN_PERF_TUNE=true
        detected=$((detected + 1))
        log STEP "   Performance-Tuning: SELFHEAL_PERF_AUTO=true → aktiviert"
    fi
    log INFO "Auto-Detect: ${detected} Module automatisch aktiviert"
}

if ! $MANUAL_FLAGS_SET && $AUTO_DETECT && ! $SHOW_HEALTH && ! $INSTALL_LAUNCHAGENT; then
    auto_detect
else
    # Manuelle Flags gesetzt oder Auto-Detect deaktiviert - bestehende Logik
    if $SELFHEAL_PERF_AUTO && ! $RUN_PERF_TUNE; then
        RUN_PERF_TUNE=true
    fi
fi

# ── START ──
rotate_logs
acquire_lock

echo -e "${BOLD}${BLUE}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║        MEISTER v0.09                     ║"
echo "  ║   macOS Wartung & Self-Healing           ║"
$DRY_RUN && echo "  ║   [DRY-RUN MODUS]                        ║"
! $MANUAL_FLAGS_SET && $AUTO_DETECT && echo "  ║   [AUTO-DETECT]                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

log INFO "Meister v0.09 gestartet ($(date))"
$DRY_RUN && log WARN "DRY-RUN: Keine Aenderungen werden vorgenommen"
log STEP "   Logfile: $LOGFILE"
[ -f "$MEISTER_CONFIG" ] && log STEP "   Config: $MEISTER_CONFIG geladen"
if ! $MANUAL_FLAGS_SET && $AUTO_DETECT; then
    log STEP "   Modus: AUTO-DETECT"
else
    log STEP "   Modus: MANUELL"
fi
log STEP "   Module: XCODE=$CLEAN_XCODE TRASH=$EMPTY_TRASH SUDO=$RUN_SUDO_TASKS CACHE=$CLEAN_CACHES LARGE=$LIST_LARGE_FILES PERF=$RUN_PERF_TUNE GIT=$RUN_GIT_REPOS DRY=$DRY_RUN"

if $SHOW_HEALTH; then health_dashboard; release_lock; exit 0; fi
if $INSTALL_LAUNCHAGENT; then install_launchagent; release_lock; exit 0; fi

# Fix #145: Sudo ZUERST holen - vor Ollama und allen Modulen
# Verhindert Password-Prompt mitten im Lauf (z.B. bei brew cask upgrade)
if ! $DRY_RUN && $NEEDS_SUDO; then
    if [ -t 0 ]; then
        log INFO "Requesting Sudo..."
        if sudo -v; then
            keep_sudo
            log INFO "   Sudo OK"
        else
            log WARN "Sudo verweigert oder Timeout - einige Operationen koennten fehlschlagen"
            log INFO "   Sudo nicht verfuegbar"
        fi
    else
        if sudo -n true 2>/dev/null; then
            keep_sudo
            log INFO "   Sudo OK (non-interactive/cached)"
        else
            log WARN "Kein interaktives Terminal + kein Sudo-Cache - sudo-Operationen uebersprungen"
            log INFO "   Sudo nicht verfuegbar (non-interactive)"
        fi
    fi
fi

# Fix #41: Zentraler Ollama-Starter + Fix #45: Modell-Check
if ollama_available || ensure_ollama_running ""; then
    log INFO "Ollama: online (${OLLAMA_MODEL})"
    local_models=$(ollama_list_cached | awk 'NR>1 {print $1}' | tr '\n' ', ')
    log STEP "   Modelle: ${local_models:-keine}"
    ensure_ollama_model
else
    log WARN "Ollama: nicht verfuegbar - kein AI-Heal"
    OLLAMA_ENABLED=false
fi

# Modul-Anzahl berechnen
MODULE_TOTAL=13
$RUN_SUDO_TASKS && MODULE_TOTAL=$((MODULE_TOTAL + 1))

# Preflight
section_header "Self-Healing Preflight"
module_timer_start
selfheal_preflight
module_timer_stop "Preflight"

if check_net; then
    run_module_safe "Homebrew"       module_homebrew
    run_module_safe "App Store"      module_mas
    run_module_safe "Ollama Models"  module_ollama
    run_module_safe "macOS System"   module_system
    run_module_safe "Cleanup"        module_cleanup
    run_module_safe "Deep Clean"     module_deepclean
    run_module_safe "Spotlight Fix"  module_spotlight_fix
    run_module_safe "iCloud Fix"     module_icloud_fix
    run_module_safe "Performance"    module_performance
    run_module_safe "Git Repos"      module_git_repos
    run_module_safe "Security Suite" module_security_suite
    run_module_safe "Benchmark"      module_benchmark

    if $RUN_SUDO_TASKS; then
        section_header "System-Wartung (sudo)"
        module_timer_start
        log INFO "Starte periodic scripts..."
        log STEP "   periodic daily..."
        run_or_dry sudo periodic daily
        log STEP "   periodic weekly..."
        run_or_dry sudo periodic weekly
        log STEP "   periodic monthly..."
        run_or_dry sudo periodic monthly
        log INFO "   DNS-Cache flush..."
        run_or_dry sudo dscacheutil -flushcache
        report_add FIX "Ran periodic scripts & DNS flush"
        module_timer_stop "System-Wartung"
    fi
else
    log ERROR "Abbruch: Kein Internet"
fi

log_analysis

# Fix #141: Ollama stoppen bevor Report (damit RAM-Info im Report stimmt)
shutdown_ollama

print_report
save_history
send_report_notification
release_lock

# Fix #38: Exit-Code 1 bei Errors
[ ${#REPORT_ERRORS[@]} -gt 0 ] && exit 1
exit 0
