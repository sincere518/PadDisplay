#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_BUNDLE="$ROOT_DIR/dist/PadDisplay.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/PadDisplay"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/build/clang-cache"
mkdir -p build

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) pkill -x PadDisplay >/dev/null 2>&1 || true ;;
  --build|--package) ;;
  *) echo "Usage: $0 [run|--build|--package|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
if [[ "$MODE" == "--package" ]]; then CONFIGURATION=release; fi
xcrun swift build --build-system native --disable-sandbox --scratch-path build/swift-native \
  --cache-path build/swift-cache -c "$CONFIGURATION" --product PadDisplay
BIN_DIR="$(xcrun swift build --build-system native --disable-sandbox --scratch-path build/swift-native \
  --cache-path build/swift-cache -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/PadDisplay" "$APP_BINARY"
cp LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
xcrun swift -module-cache-path build/icon-cache script/make_icon.swift "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.PadDisplay</string>
<key>CFBundleName</key><string>PadDisplay</string>
<key>CFBundleDisplayName</key><string>PadDisplay</string>
<key>CFBundleExecutable</key><string>PadDisplay</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP_BUNDLE"
codesign --verify --strict --deep "$APP_BUNDLE"

case "$MODE" in
  --build) ;;
  --package)
    ditto -c -k --keepParent "$APP_BUNDLE" "$ROOT_DIR/dist/PadDisplay-0.1.0-arm64.zip"
    shasum -a 256 "$ROOT_DIR/dist/PadDisplay-0.1.0-arm64.zip" > "$ROOT_DIR/dist/SHA256SUMS.txt"
    ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "PadDisplay"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x PadDisplay >/dev/null
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
