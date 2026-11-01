#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-}"
[[ -z "$REF" ]] && { echo "Usage: $0 <tag>"; exit 1; }
SRC="$ROOT_DIR/.native/sing-box-for-android"
DST="$ROOT_DIR/native/android/src"
PROBE="/tmp/sfa-probe-$REF"

rm -rf "$PROBE"
echo "Cloning $REF..."
if ! git clone --depth 1 --branch "$REF" https://github.com/SagerNet/sing-box-for-android.git "$PROBE"; then
  echo "Clone failed for $REF" >&2; exit 1
fi

mkdir -p "$DST"
for f in VPNService.kt BoxService.kt PlatformInterfaceWrapper.kt; do
  src=$(find "$PROBE/app/src/main/java" -name "$f" 2>/dev/null | head -1)
  if [[ -n "$src" ]]; then
    sed 's/^package .*/package __BEHINET_PACKAGE__.vpn/' "$src" > "$DST/$f"
    echo "Copied: $f"
  else
    echo "MISSING: $f (check $REF structure)"
  fi
done
