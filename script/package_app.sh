#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="debug"
DIST_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration|-c)
      CONFIGURATION="$2"
      shift 2
      ;;
    --output)
      DIST_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "usage: $0 [--configuration debug|release] [--output <directory>]" >&2
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      echo "usage: $0 [--configuration debug|release] [--output <directory>]" >&2
      exit 2
      ;;
  esac
done

APP_NAME="CodexAutofocusMenuBar"
DISPLAY_NAME="Codex Autofocus"
BUNDLE_ID="com.jonasjancarik.codex-autofocus"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
HELPER_BINARY="$APP_RESOURCES/codex-autofocus"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION" --product codex-autofocus
swift build --configuration "$CONFIGURATION" --product "$APP_NAME"
BUILD_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_HELPER="$BUILD_DIR/codex-autofocus"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER" "$HELPER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$HELPER_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$APP_BUNDLE"
