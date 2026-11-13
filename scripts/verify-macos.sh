#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Lumakey only supports Apple Silicon (arm64)." >&2
  exit 1
fi

if [[ "$(sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" == "1" ]]; then
  echo "ERROR: Rosetta translated shell is not allowed." >&2
  exit 1
fi

echo "==> Clean Code line limit check (Sources/*.swift <= 300 lines)"
while IFS= read -r -d '' file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  if (( lines > 300 )); then
    echo "ERROR: $file has $lines lines (exceeds Clean Code limit of 300)." >&2
    exit 1
  fi
done < <(find "$ROOT_DIR/Sources" -type f -name "*.swift" -print0)

echo "==> Checking Info.plist"
plutil -lint "$ROOT_DIR/apps/macos/Info.plist"

echo "==> Checking documentation links and index coverage"
python3 -B "$ROOT_DIR/scripts/check-docs.py"

echo "==> Building Swift 6 targets (arm64 debug)"
swift build -c debug --arch arm64

BIN_DIR="$(swift build -c debug --arch arm64 --show-bin-path)"
for bin in Lumakey lumakey-mcp lumakey-check; do
  archs=$(lipo -archs "$BIN_DIR/$bin")
  if [[ "$archs" != "arm64" ]]; then
    echo "ERROR: $bin architecture is '$archs', expected 'arm64'." >&2
    exit 1
  fi
done

echo "==> Running LumakeyCheck + real lumakey-mcp subprocess verification"
"$BIN_DIR/lumakey-check"
