#!/bin/zsh
# Installs the app in ~/Applications and opens it at every login.
# launchd may be refused access to ~/Downloads, so the app cannot start from the project folder.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d build/Temperatura.app ]] || scripts/build-app.sh

label=local.temperatura.monitor
app="$HOME/Applications/Temperatura.app"
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

launchctl bootout "$domain/$label" 2>/dev/null || true
pkill -f 'Temperatura.app/Contents/MacOS/Temperatura$' || true

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$app"
cp -R build/Temperatura.app "$app"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array><string>$app/Contents/MacOS/Temperatura</string></array>
    <key>RunAtLoad</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
plutil -lint "$plist"
launchctl bootstrap "$domain" "$plist"
echo "Instalado: $app"
