#!/bin/zsh
# Builds build/Temperatura.app (menu bar app, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Temperatura

app=build/Temperatura.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Temperatura" "$app/Contents/MacOS/Temperatura"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Temperatura</string>
    <key>CFBundleDisplayName</key><string>Temperatura</string>
    <key>CFBundleIdentifier</key><string>local.temperatura.monitor</string>
    <key>CFBundleExecutable</key><string>Temperatura</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "$app"
