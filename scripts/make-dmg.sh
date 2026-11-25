#!/usr/bin/env bash
# Builds the release app and packs it into dist/JK-LiveBridge-<version>.dmg (drag it to Applications).
# The app is ad-hoc signed, not notarised: on another Mac the first launch needs "Open Anyway" (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="JK - LiveBridge"
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' apps/desktop/pubspec.yaml)
APP="apps/desktop/build/macos/Build/Products/Release/$NAME.app"
OUT="dist/JK-LiveBridge-$VERSION.dmg"

(cd apps/desktop && flutter build macos --release)

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$OUT"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" > /dev/null
echo "$OUT"
