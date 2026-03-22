#!/bin/bash
# release.sh - Neues Homebrew-Release von meister2026.sh erstellen
#
# 1. Pusht meister2026.sh nach maf4711/meister
# 2. Erstellt GitHub Release mit Tag
# 3. Holt SHA256 des Tarballs
# 4. Aktualisiert Formula + pusht homebrew-meister Tap
#
# Usage: ./release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="/Users/a321/Developer/meister/meister2026.sh"
MEISTER_REPO="/Users/a321/Developer/meister"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"

# Version aus Script extrahieren
VERSION=$(grep -m1 '^# Version:' "$SOURCE" | awk '{print $3}')
if [[ -z "$VERSION" ]]; then
    echo "FEHLER: Version nicht gefunden in $SOURCE"
    exit 1
fi

echo "=== meister Release v${VERSION} ==="
echo ""

# 1. meister Repo aktualisieren
echo "--- Schritt 1: meister Repo aktualisieren ---"
cd "$MEISTER_REPO"
git add meister2026.sh
if git diff --cached --quiet; then
    echo "Keine Aenderungen in meister2026.sh"
else
    git commit -m "feat: meister v${VERSION}"
    git push origin main
    echo "meister2026.sh gepusht"
fi

# 2. GitHub Release erstellen
echo ""
echo "--- Schritt 2: GitHub Release v${VERSION} ---"
if gh release view "v${VERSION}" -R maf4711/meister &>/dev/null; then
    echo "Release v${VERSION} existiert bereits - loesche und erstelle neu"
    gh release delete "v${VERSION}" -R maf4711/meister --yes
    git tag -d "v${VERSION}" 2>/dev/null || true
    git push origin ":refs/tags/v${VERSION}" 2>/dev/null || true
fi
gh release create "v${VERSION}" -R maf4711/meister \
    --title "meister v${VERSION}" \
    --notes "macOS Maintenance & Self-Healing Script v${VERSION}"
echo "Release erstellt: https://github.com/maf4711/meister/releases/tag/v${VERSION}"

# 3. SHA256 des Tarballs holen
echo ""
echo "--- Schritt 3: SHA256 berechnen ---"
TARBALL_URL="https://github.com/maf4711/meister/archive/refs/tags/v${VERSION}.tar.gz"
TMPTAR=$(mktemp)
curl -sL "$TARBALL_URL" -o "$TMPTAR"
SHA=$(shasum -a 256 "$TMPTAR" | awk '{print $1}')
rm -f "$TMPTAR"
echo "URL:     $TARBALL_URL"
echo "SHA256:  $SHA"

# 4. Formula aktualisieren
echo ""
echo "--- Schritt 4: Formula aktualisieren ---"
sed -i '' "s|version \".*\"|version \"${VERSION}\"|" "$FORMULA"
sed -i '' "s|v[0-9][0-9]*\.[0-9][0-9]*\.tar\.gz|v${VERSION}.tar.gz|" "$FORMULA"
sed -i '' "s|sha256 \".*\"|sha256 \"${SHA}\"|" "$FORMULA"
echo "Formula aktualisiert: $FORMULA"

# 5. homebrew-meister Tap pushen
echo ""
echo "--- Schritt 5: Tap pushen ---"
cd "$SCRIPT_DIR"
git add -A
if git diff --cached --quiet; then
    echo "Keine Aenderungen im Tap"
else
    git commit -m "meister v${VERSION}"
    git push origin main
    echo "Tap gepusht"
fi

# 6. Lokalen Brew-Cache invalidieren
CACHE_FILE=$(brew --cache meister 2>/dev/null || true)
[ -f "$CACHE_FILE" ] && rm -f "$CACHE_FILE"

# Fertig

echo ""
echo "=== Release v${VERSION} fertig! ==="
echo ""
echo "Andere User installieren mit:"
echo "  brew tap maf4711/meister"
echo "  brew install meister"
echo ""
echo "Du aktualisierst lokal mit:"
echo "  brew update && brew upgrade meister"
