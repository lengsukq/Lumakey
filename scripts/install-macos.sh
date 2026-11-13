#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash "$ROOT_DIR/scripts/build-macos.sh"

APP_DIR="$ROOT_DIR/dist/Lumakey.app"
DMG_PATH="$ROOT_DIR/dist/Lumakey.dmg"
STAGE_DIR="$ROOT_DIR/.build/dmg-stage"
DEST_APP="/Applications/Lumakey.app"

rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/Lumakey.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Packaging $DMG_PATH"
hdiutil create -volname "Lumakey" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"

echo "==> Stopping any running Lumakey instances"
pkill -x Lumakey || true
sleep 0.5

echo "==> Installing to $DEST_APP (in-place sync)"
mkdir -p "$DEST_APP"
rsync -a --delete "$APP_DIR/" "$DEST_APP/"

echo "==> Verifying installed bundle & signature"
codesign --verify --deep --strict "$DEST_APP"
archs=$(lipo -archs "$DEST_APP/Contents/MacOS/Lumakey")
if [[ "$archs" != "arm64" ]]; then
  echo "ERROR: Installed Lumakey architecture is '$archs', expected 'arm64'." >&2
  exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" || true
fi

echo "Installed $DEST_APP and packaged $DMG_PATH successfully."
