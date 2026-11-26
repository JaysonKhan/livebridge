#!/usr/bin/env bash
# Builds the release app and packs it into dist/JK-LiveBridge-<version>.dmg: a window with the app, an arrow and
# Applications, on the brand background drawn by scripts/dmg/background.swift (laid out by dmgbuild, so Finder is not
# scripted). The app is ad-hoc signed, not notarised: on another Mac the first launch needs "Open Anyway" (see README).
# SKIP_BUILD=1 packs the app that is already built.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="JK - LiveBridge"
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' apps/desktop/pubspec.yaml)
APP="apps/desktop/build/macos/Build/Products/Release/$NAME.app"
OUT="dist/JK-LiveBridge-$VERSION.dmg"
VENV="scripts/dmg/.venv"

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  (cd apps/desktop && flutter build macos --release)
fi
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

# dmgbuild writes the window layout itself; it lives in a git-ignored venv next to its settings.
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild==2.0.*"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swift scripts/dmg/background.swift "$WORK/background.png" "$WORK/background@2x.png"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" 2> /dev/null

mkdir -p dist
rm -f "$OUT"
"$VENV/bin/dmgbuild" -s scripts/dmg/settings.py -D app="$APP" -D background="$WORK/background.tiff" "$NAME" "$OUT" \
  > /dev/null
echo "$OUT"
