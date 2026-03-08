#!/bin/bash
# release.sh - Neues Homebrew-Release von meister2026.sh erstellen
#
# Erstellt Archiv, aktualisiert SHA256 und Version in der Formula.
# Usage: ./release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="/Users/a321/Documents/Tech/Scripts/bin/meister2026.sh"
FORMULA="$SCRIPT_DIR/Formula/meister.rb"
DIST_DIR="$SCRIPT_DIR/dist"

# Version aus Script extrahieren
VERSION=$(grep -m1 '^# Version:' "$SOURCE" | awk '{print $3}')
if [[ -z "$VERSION" ]]; then
    echo "FEHLER: Version nicht gefunden in $SOURCE"
    exit 1
fi

echo "=== meister Release v${VERSION} ==="

# Archiv erstellen
mkdir -p "$DIST_DIR"
ARCHIVE="$DIST_DIR/meister-${VERSION}.tar.gz"

TMPDIR_RELEASE=$(mktemp -d)
mkdir -p "$TMPDIR_RELEASE/meister-${VERSION}"
cp "$SOURCE" "$TMPDIR_RELEASE/meister-${VERSION}/"
tar czf "$ARCHIVE" -C "$TMPDIR_RELEASE" "meister-${VERSION}/"
rm -rf "$TMPDIR_RELEASE"

# SHA256 berechnen
SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')

echo "Archiv:  $ARCHIVE"
echo "SHA256:  $SHA"
echo "Version: $VERSION"

# Formula aktualisieren
sed -i '' "s|version \".*\"|version \"${VERSION}\"|" "$FORMULA"
sed -i '' "s|meister-.*\.tar\.gz|meister-${VERSION}.tar.gz|" "$FORMULA"
sed -i '' "s|sha256 \".*\"|sha256 \"${SHA}\"|" "$FORMULA"

echo ""
echo "Formula aktualisiert: $FORMULA"
echo ""
echo "Jetzt ausfuehren:"
echo "  brew upgrade meister"
echo ""
echo "Oder bei Erstinstallation:"
echo "  brew tap a321/meister $SCRIPT_DIR"
echo "  brew install meister"
