#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build >&2

APP_DIR="$PWD/.build/AgentsPet.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$PWD/Resources/AgentsPetIcon.svg"
ICONSET_DIR="$PWD/.build/AgentsPet.iconset"
ICON_FILE="$PWD/.build/AgentsPet.icns"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$PWD/.build/debug/AgentsPet" "$MACOS_DIR/AgentsPet"

if [[ -f "$ICON_SOURCE" ]] && command -v magick >/dev/null 2>&1; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  for size in 16 32 128 256 512; do
    magick -background none "$ICON_SOURCE" -resize "${size}x${size}" "$ICONSET_DIR/icon_${size}x${size}.png"
    magick -background none "$ICON_SOURCE" -resize "$((size * 2))x$((size * 2))" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
  done

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
  cp "$ICON_FILE" "$RESOURCES_DIR/AgentsPet.icns"
fi

if [[ -d "$PWD/Resources/MahjongTiles" ]]; then
  cp -R "$PWD/Resources/MahjongTiles" "$RESOURCES_DIR/MahjongTiles"
fi

if [[ -d "$PWD/Resources/AgentIcons" ]]; then
  cp -R "$PWD/Resources/AgentIcons" "$RESOURCES_DIR/AgentIcons"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>AgentsPet</string>
  <key>CFBundleIconFile</key>
  <string>AgentsPet</string>
  <key>CFBundleIdentifier</key>
  <string>local.agentspet.mvp</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>AgentsPet</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "$APP_DIR"
