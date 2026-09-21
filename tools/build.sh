#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="dist/Pingvi.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bridge"
cp .build/release/AgentAttention "$app/Contents/MacOS/AgentAttention"
cp bridge/*.py "$app/Contents/Resources/bridge/"
for artwork in Assets/*.png; do
    sips -z 512 512 "$artwork" --out "$app/Contents/Resources/$(basename "$artwork")" >/dev/null
done
iconset=".build/Pingvi.iconset"
mkdir -p "$iconset"
/usr/bin/python3 tools/prepare_icons.py
for size in 16 32 128 256 512; do
    cp ".build/PingviAssets.xcassets/AppIcon.appiconset/icon_${size}x${size}@1x.png" "$iconset/icon_${size}x${size}.png"
    cp ".build/PingviAssets.xcassets/AppIcon.appiconset/icon_${size}x${size}@2x.png" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Pingvi.icns"
xcrun actool .build/PingviAssets.xcassets --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist .build/icon-info.plist
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.pingvi.mac</string>
<key>CFBundleName</key><string>Pingvi</string>
<key>CFBundleDisplayName</key><string>Pingvi</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleExecutable</key><string>AgentAttention</string>
<key>CFBundleVersion</key><string>18</string>
<key>CFBundleShortVersionString</key><string>0.7.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Чтение вопросов агентов и открытие нужной вкладки Terminal.</string>
<key>NSLocalNetworkUsageDescription</key><string>Pingvi передаёт вопросы и ответы напрямую вашим личным устройствам в локальной сети.</string>
<key>NSBonjourServices</key><array><string>_pingvi._tcp</string></array>
</dict></plist>
PLIST
python3 tools/embed-python.py "$app"
python3 tools/sign-app.py "$app"
echo "$PWD/$app"
