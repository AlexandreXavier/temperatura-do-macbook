#!/bin/zsh
# Stops the app and removes the login agent and the installed copy. The history CSV is kept.
set -euo pipefail

label=local.temperatura.monitor
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
pkill -f 'Temperatura.app/Contents/MacOS/Temperatura$' || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Applications/Temperatura.app"
echo "Removido."
