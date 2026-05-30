#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="$(script/build_app.sh)"
DIST_DIR="$PWD/.build/dist"
ZIP_PATH="$DIST_DIR/mahjong.zip"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
