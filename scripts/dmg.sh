#!/bin/sh
# Packages dist/AulaStudio.app into dist/AulaStudio-<version>.dmg with an Applications shortcut.
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-dev}"
export VERSION
./scripts/bundle.sh
STAGE=$(mktemp -d)
cp -R dist/AulaStudio.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
OUT="dist/AulaStudio-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Aula Studio" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"
echo "built $OUT"
