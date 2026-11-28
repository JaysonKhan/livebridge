#!/usr/bin/env bash
# Builds the release app and packs it into dist/JK-LiveBridge-<version>.dmg: a window with the app, an arrow and
# Applications, on the brand background drawn by scripts/dmg/background.swift (laid out by dmgbuild, so Finder is not
# scripted). Not notarised: on another Mac the first launch needs "Open Anyway" (see README).
#
# Signing: the app and the DMG are signed with the stable self-signed identity named in LIVEBRIDGE_SIGN_IDENTITY
# (default "JK - LiveBridge self-signed", kept in the maintainer's login keychain, never in the repo; see
# docs/deployment.md). A stable identity keeps the app's code requirement the same from one release to the next, so
# Keychain access granted once survives updates. Without that identity the app stays ad-hoc signed, with a warning.
# SKIP_BUILD=1 packs the app that is already built.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="JK - LiveBridge"
VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' apps/desktop/pubspec.yaml)
APP="apps/desktop/build/macos/Build/Products/Release/$NAME.app"
OUT="dist/JK-LiveBridge-$VERSION.dmg"
VENV="scripts/dmg/.venv"
IDENTITY="${LIVEBRIDGE_SIGN_IDENTITY:-JK - LiveBridge self-signed}"

if [[ "${SKIP_BUILD:-}" != "1" ]]; then
  (cd apps/desktop && flutter build macos --release)
fi
[[ -d "$APP" ]] || { echo "missing $APP" >&2; exit 1; }

# Nested frameworks first, then the app with its entitlements; Xcode's release build is ad-hoc signed.
if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  for item in "$APP"/Contents/Frameworks/*; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$item"
  done
  codesign --force --timestamp=none --sign "$IDENTITY" --entitlements apps/desktop/macos/Runner/Release.entitlements "$APP"
  codesign --verify --deep --strict "$APP"
  SIGNED=1
else
  echo "warning: no code-signing identity \"$IDENTITY\": the app stays ad-hoc signed, so Keychain access is asked" \
    "for again after every update" >&2
  SIGNED=0
fi

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
if [[ "$SIGNED" == "1" ]]; then codesign --force --timestamp=none --sign "$IDENTITY" "$OUT"; fi
echo "$OUT"
