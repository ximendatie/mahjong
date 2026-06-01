#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build >&2

VERSION="${MAHJONG_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${MAHJONG_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP_DIR="$PWD/.build/mahjong.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$PWD/Resources/MahjongTiles/red.png"
ICON_WORK_DIR="$(mktemp -d "$PWD/.build/mahjong-icons.XXXXXX")"
ICONSET_DIR="$ICON_WORK_DIR/mahjong.iconset"
ICON_FILE="$ICON_WORK_DIR/mahjong.icns"

cleanup() {
  rm -rf "$ICON_WORK_DIR"
}
trap cleanup EXIT

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$PWD/.build/debug/mahjong" "$MACOS_DIR/mahjong"

if [[ -f "$ICON_SOURCE" ]] && command -v iconutil >/dev/null 2>&1; then
  mkdir -p "$ICONSET_DIR"

  for size in 16 32 128 256 512; do
    if command -v magick >/dev/null 2>&1; then
      magick -background none "$ICON_SOURCE" -resize "${size}x${size}" "$ICONSET_DIR/icon_${size}x${size}.png"
      magick -background none "$ICON_SOURCE" -resize "$((size * 2))x$((size * 2))" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
    elif command -v sips >/dev/null 2>&1; then
      sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
      sips -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    fi
  done

  if [[ -f "$ICONSET_DIR/icon_512x512@2x.png" ]]; then
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
    cp "$ICON_FILE" "$RESOURCES_DIR/mahjong.icns"
  fi
fi

if [[ -d "$PWD/Resources/MahjongTiles" ]]; then
  cp -R "$PWD/Resources/MahjongTiles" "$RESOURCES_DIR/MahjongTiles"
fi

if [[ -d "$PWD/Resources/AgentIcons" ]]; then
  cp -R "$PWD/Resources/AgentIcons" "$RESOURCES_DIR/AgentIcons"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>mahjong</string>
  <key>CFBundleIconFile</key>
  <string>mahjong</string>
  <key>CFBundleIdentifier</key>
  <string>local.mahjong.mvp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>mahjong</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
