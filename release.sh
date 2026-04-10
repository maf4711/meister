#!/bin/bash
# release.sh - Neues Homebrew-Release erstellen (single-repo)
#
# 1. Liest Version aus meister2026.sh
# 2. Erstellt GitHub Release mit Tag
# 3. Aktualisiert SHA256 in Formula
# 4. Pusht alles
#
# Usage: ./release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/meister2026.sh"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"
REPO="maf4711/homebrew-meister"

# Version aus Script extrahieren
VERSION=$(grep -m1 '^# Version:' "$SOURCE" | awk '{print $3}')
if [[ -z "$VERSION" ]]; then
    echo "FEHLER: Version nicht gefunden in $SOURCE"
    exit 1
fi

echo "=== meister Release v${VERSION} ==="
echo ""

# 1. Alle Aenderungen committen und pushen
echo "--- Schritt 1: Repo aktualisieren ---"
cd "$SCRIPT_DIR"
git add meister2026.sh tools/ Formula/ LICENSE .gitignore
if git diff --cached --quiet; then
    echo "Keine Aenderungen"
else
    git commit -m "meister v${VERSION}"
    git push origin main
    echo "Gepusht"
fi

# 2. GitHub Release erstellen
echo ""
echo "--- Schritt 2: GitHub Release v${VERSION} ---"
if gh release view "v${VERSION}" -R "$REPO" &>/dev/null; then
    echo "Release v${VERSION} existiert bereits - loesche und erstelle neu"
    gh release delete "v${VERSION}" -R "$REPO" --yes
    git tag -d "v${VERSION}" 2>/dev/null || true
    git push origin ":refs/tags/v${VERSION}" 2>/dev/null || true
fi
gh release create "v${VERSION}" -R "$REPO" \
    --title "meister v${VERSION}" \
    --notes "macOS Maintenance & Self-Healing Script v${VERSION}"
echo "Release erstellt: https://github.com/$REPO/releases/tag/v${VERSION}"

# 3. SHA256 des Tarballs holen
echo ""
echo "--- Schritt 3: SHA256 berechnen ---"
TARBALL_URL="https://github.com/$REPO/archive/refs/tags/v${VERSION}.tar.gz"
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
echo "Formula aktualisiert"

# 5. Formula-Update committen und pushen
echo ""
echo "--- Schritt 5: Formula-Update pushen ---"
git add Formula/meister.rb
if git diff --cached --quiet; then
    echo "Keine Aenderungen"
else
    git commit -m "formula: update SHA256 for v${VERSION}"
    git push origin main
    echo "Gepusht"
fi

# 6. Lokalen Brew-Cache invalidieren
CACHE_FILE=$(brew --cache meister 2>/dev/null || true)
[ -f "$CACHE_FILE" ] && rm -f "$CACHE_FILE"

echo ""
echo "=== Release v${VERSION} fertig! ==="
echo ""
echo "Andere User installieren mit:"
echo "  brew tap maf4711/meister"
echo "  brew install meister"
echo ""
echo "Du aktualisierst lokal mit:"
echo "  brew update && brew upgrade meister"
