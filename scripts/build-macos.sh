#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Lumakey only builds on Apple Silicon (arm64)." >&2
  exit 1
fi

echo "==> Building release binaries (arm64, -O + dead_strip)"
swift build -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --product Lumakey
swift build -c release --arch arm64 -Xswiftc -O -Xlinker -dead_strip --product lumakey-mcp

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/Lumakey.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$ROOT_DIR/.build/Lumakey.iconset"

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Generating Retina Liquid Glass AppIcon.icns"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

cp "$ROOT_DIR/apps/macos/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/Lumakey" "$MACOS_DIR/Lumakey"
cp "$BIN_DIR/lumakey-mcp" "$MACOS_DIR/lumakey-mcp"
chmod +x "$MACOS_DIR/Lumakey" "$MACOS_DIR/lumakey-mcp"
/usr/bin/strip -x "$MACOS_DIR/Lumakey" "$MACOS_DIR/lumakey-mcp"

for bin in Lumakey lumakey-mcp; do
  archs=$(lipo -archs "$MACOS_DIR/$bin")
  if [[ "$archs" != "arm64" ]]; then
    echo "ERROR: $bin architecture is '$archs', expected 'arm64'." >&2
    exit 1
  fi
done

select_signing_identity() {
  if [[ -n "${LUMAKEY_SIGN_IDENTITY:-}" ]]; then
    echo "$LUMAKEY_SIGN_IDENTITY"
    return
  fi
  local identities
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  local match
  for pattern in '"Developer ID Application:[^"]*"' '"Apple Development:[^"]*"' '"Mac Developer:[^"]*"' '"Lumakey Local Signer"'; do
    match=$(printf '%s\n' "$identities" | grep -oE "$pattern" | head -n 1 | tr -d '"' || true)
    if [[ -n "$match" ]]; then
      echo "$match"
      return
    fi
  done
  match=$(printf '%s\n' "$identities" | grep -oE '"[^"]+"' | head -n 1 | tr -d '"' || true)
  if [[ -n "$match" ]]; then
    echo "$match"
  else
    echo "-"
  fi
}

SIGN_ID="$(select_signing_identity)"
if [[ "$SIGN_ID" == "-" ]]; then
  echo "==> Ad-hoc codesigning Lumakey.app (Tip: run 'bash scripts/setup-local-signing.sh' once for stable macOS TCC permissions)"
else
  echo "==> Codesigning Lumakey.app with stable Keychain identity: $SIGN_ID"
fi

codesign --force --sign "$SIGN_ID" --identifier "app.lumakey.macos.mcp" "$MACOS_DIR/lumakey-mcp"
codesign --force --sign "$SIGN_ID" --identifier "app.lumakey.macos" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
codesign -d -r- "$APP_DIR" 2>&1 || true
plutil -lint "$CONTENTS_DIR/Info.plist"

echo "Built $APP_DIR successfully (arm64 only, includes Lumakey + lumakey-mcp + AppIcon.icns)."
