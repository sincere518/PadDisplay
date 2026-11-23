#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT_DIR"
MODE="${1:-run}"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_BUNDLE="$ROOT_DIR/dist/PadDisplay.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/PadDisplay"
VERSION=0.4.1
BUILD=10
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/build/clang-cache"
mkdir -p build

LAUNCH=false
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) LAUNCH=true ;;
  --build|--package) ;;
  *) echo "Usage: $0 [run|--build|--package|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
check_running_apps() {
  local pids status=0 pid process_path
  pids=$(/usr/bin/pgrep -x PadDisplay) || status=$?
  if [[ "$status" != 0 ]]; then
    if [[ "$status" == 1 ]]; then return 0; fi
    echo "无法确认 PadDisplay 的运行状态。" >&2
    exit 1
  fi
  for pid in $pids; do
    if ! process_path=$(/bin/ps -ww -p "$pid" -o comm= 2>/dev/null); then
      if ! kill -0 "$pid" 2>/dev/null; then continue; fi
      echo "无法确认当前 PadDisplay 的应用路径。" >&2
      exit 1
    fi
    if [[ "$process_path" == "$APP_BINARY" ]]; then
      echo "请先退出项目目录中的 PadDisplay，再重新构建或打包。" >&2
      exit 1
    elif [[ "$LAUNCH" == true ]]; then
      echo "其他位置的 PadDisplay 正在运行，请先在该应用中退出。" >&2
      exit 1
    fi
  done
}
check_running_apps
SIGNING_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$ROOT_DIR/script/signing.identity.local" ]]; then
  IFS= read -r SIGNING_IDENTITY < "$ROOT_DIR/script/signing.identity.local" || true
fi
if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == - ]]; then
  echo "请配置固定的 Apple 签名证书：设置 SIGN_IDENTITY，或把证书 SHA-1 写入 script/signing.identity.local。" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | awk -v identity="$SIGNING_IDENTITY" \
  '$2 == identity || index($0, "\"" identity "\"") > 0 { found = 1 } END { exit !found }'; then
  echo "配置的签名证书不可用，请检查钥匙串中的有效证书及对应私钥。" >&2
  exit 1
fi
if [[ "$MODE" == "--package" ]]; then CONFIGURATION=release; fi
xcrun swift build --build-system native --disable-sandbox --scratch-path build/swift-native \
  --cache-path build/swift-cache -c "$CONFIGURATION" --product PadDisplay
BIN_DIR="$(xcrun swift build --build-system native --disable-sandbox --scratch-path build/swift-native \
  --cache-path build/swift-cache -c "$CONFIGURATION" --show-bin-path)"
if [[ "$MODE" == "--package" && "$(/usr/bin/lipo -archs "$BIN_DIR/PadDisplay")" != arm64 ]]; then
  echo "发布安装包要求 arm64 应用，请用 Apple Silicon 的原生 Xcode 工具链打包。" >&2
  exit 1
fi
check_running_apps
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/PadDisplay" "$APP_BINARY"
cp LICENSE "$APP_BUNDLE/Contents/Resources/LICENSE.txt"
cp Resources/DevicePreviews/iphone-frame.png "$APP_BUNDLE/Contents/Resources/"
cp Resources/DevicePreviews/ASSET-NOTICE.txt "$APP_BUNDLE/Contents/Resources/"
xcrun swift -module-cache-path build/icon-cache script/make_icon.swift "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.PadDisplay</string>
<key>CFBundleName</key><string>PadDisplay</string>
<key>CFBundleDisplayName</key><string>PadDisplay</string>
<key>CFBundleExecutable</key><string>PadDisplay</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>local.PadDisplay.shortcuts</string><key>CFBundleURLSchemes</key><array><string>paddisplay</string></array></dict></array>
</dict></plist>
PLIST
codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$APP_BUNDLE"
codesign --verify --strict --deep "$APP_BUNDLE"

case "$MODE" in
  --build) ;;
  --package)
    ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ROOT_DIR/dist/PadDisplay-$VERSION-arm64.zip"
    DMG_STAGE="$ROOT_DIR/build/dmg-stage"
    rm -rf "$DMG_STAGE"
    mkdir -p "$DMG_STAGE"
    ditto "$APP_BUNDLE" "$DMG_STAGE/PadDisplay.app"
    ln -s /Applications "$DMG_STAGE/Applications"
    hdiutil create -volname PadDisplay -srcfolder "$DMG_STAGE" -fs HFS+ -format UDZO -ov "$ROOT_DIR/dist/PadDisplay-$VERSION-arm64.dmg"
    rm -rf "$DMG_STAGE"
    python3 script/make_update_manifest.py "$VERSION" "$BUILD" "$ROOT_DIR/dist" "${RELEASE_BASE_URL:-https://github.com/sincere518/PadDisplay/releases/download/v$VERSION}"
    (cd "$ROOT_DIR/dist" && shasum -a 256 "PadDisplay-$VERSION-arm64.zip" "PadDisplay-$VERSION-arm64.dmg" PadDisplay-update.json) > "$ROOT_DIR/dist/SHA256SUMS.txt"
    ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "PadDisplay"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    verified=false
    for pid in $(pgrep -x PadDisplay || true); do
      [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" != "$APP_BINARY" ]] || verified=true
    done
    [[ "$verified" == true ]]
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
