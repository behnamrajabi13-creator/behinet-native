#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SINGBOX_DIR="${SINGBOX_DIR:-$ROOT_DIR/.native/sing-box}"
SINGBOX_REF="${SINGBOX_REF:?Set SINGBOX_REF to an immutable tag, e.g. v1.11.15}"
OUTPUT_DIR="$ROOT_DIR/native/android/libs"

for cmd in git go java make; do command -v $cmd >/dev/null || { echo "$cmd required" >&2; exit 1; }; done
java -version 2>&1 | grep -q 'version "17' || { echo "JDK 17 required" >&2; exit 1; }

if [[ ! -d "$SINGBOX_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SINGBOX_DIR")"
  git clone --depth 1 --branch "$SINGBOX_REF" https://github.com/SagerNet/sing-box.git "$SINGBOX_DIR"
else
  git -C "$SINGBOX_DIR" fetch --depth 1 origin "$SINGBOX_REF"
  git -C "$SINGBOX_DIR" checkout -q FETCH_HEAD
fi
cd "$SINGBOX_DIR"
go mod download
make lib_install
go run ./cmd/internal/build_libbox -target android
mkdir -p "$OUTPUT_DIR"
cp -f libbox.aar "$OUTPUT_DIR/libbox.aar"
cp -f libbox-legacy.aar "$OUTPUT_DIR/libbox-legacy.aar"
echo "Built: $OUTPUT_DIR/libbox.aar"
