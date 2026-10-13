#!/bin/zsh
# 构建「UUyc companion.app」（中文系统显示为「UU远程伴侣」，「UUDisplay Signing」证书签名）。
# 用法：scripts/build-app.sh [--install]
# 对外名称已改，内部标识保持不变：Bundle ID com.corndog.uudisplay（辅助功能授权按它识别）、
# 可执行文件 UUDisplay / UUDisplayWatchdog、配置目录与日志文件名
# 固定证书签名后，签名要求不随每次构建变化，升级后「辅助功能」等授权可保留（ad-hoc 签名每次都会失效）
# --install：复制到 /Applications 并启动
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP_NAME="UUyc companion"
APP="build/$APP_NAME.app"
LEGACY_APP="/Applications/UUDisplay.app"   # 改名前的安装位置
SIGN_IDENTITY="${SIGN_IDENTITY:-UUDisplay Signing}"

# SIGN_IDENTITY=- 表示 ad-hoc 签名（没有证书时从源码构建用；每次构建后辅助功能授权会失效）
if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
  echo "❌ 钥匙串中找不到有效的代码签名证书「$SIGN_IDENTITY」；没有证书可用 SIGN_IDENTITY=- 改为 ad-hoc 签名" >&2
  exit 1
fi

swift build -c release --build-system native --product UUDisplay
BIN="$(swift build -c release --build-system native --show-bin-path)/UUDisplay"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/UUDisplay"
# 看门狗用独立文件名，避免 killall/pkill UUDisplay 时连同看门狗一起结束
cp "$BIN" "$APP/Contents/MacOS/UUDisplayWatchdog"
# PermissionFlow 资源包（本地化文案等），放 Contents/Resources 供 PermissionFlowResources 查找
cp -R "$(dirname "$BIN")/PermissionFlow_PermissionFlow.bundle" "$APP/Contents/Resources/"
# 功能导览配图（TourKit 从 Bundle.main 的 Resources 根目录按文件名查找）
cp Assets/Tour/*.png "$APP/Contents/Resources/"
# App 图标与菜单栏模板图（见 Assets/AppIcon/README.md）
cp Assets/AppIcon/AppIcon.icns Assets/AppIcon/MenuBarIconTemplate.png Assets/AppIcon/MenuBarIconTemplate@2x.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.corndog.uudisplay</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>CFBundleName</key><string>UUyc companion</string>
  <key>CFBundleDisplayName</key><string>UUyc companion</string>
  <key>LSHasLocalizedDisplayName</key><true/>
  <key>CFBundleExecutable</key><string>UUDisplay</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# 看门狗 LaunchAgent 由 App 运行时写入 ~/Library/LaunchAgents 并用 launchctl 加载（见 WatchdogAgent）
# 本地化名称：中文系统显示「UU远程伴侣」，其他语言显示「UUyc companion」
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
printf '"CFBundleDisplayName" = "UU远程伴侣";\n"CFBundleName" = "UU远程伴侣";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
printf '"CFBundleDisplayName" = "UUyc companion";\n"CFBundleName" = "UUyc companion";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"

# 先签内嵌的看门狗可执行文件，再签整个 App
codesign --force --sign "$SIGN_IDENTITY" --identifier com.corndog.uudisplay.watchdog "$APP/Contents/MacOS/UUDisplayWatchdog"
codesign --force --sign "$SIGN_IDENTITY" --identifier com.corndog.uudisplay "$APP"
codesign --verify --strict --deep "$APP"
echo "✅ 已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x UUDisplay 2>/dev/null && sleep 1 || true
  pkill -x UUDisplayWatchdog 2>/dev/null || true
  rm -rf "$LEGACY_APP" "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
  echo "✅ 已安装到 /Applications 并启动"
fi
