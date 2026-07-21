#!/usr/bin/env bash
# Разовая установка (запускать через sudo). Требует заранее созданный
# ~/.config/wg0-nets/template.conf (см. macos/README.md) и установленный
# `brew install wireguard-tools`.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите через sudo" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory | awk '{print $2}')"

if [ ! -f "$REAL_HOME/.config/wg0-nets/template.conf" ]; then
    echo "Нет $REAL_HOME/.config/wg0-nets/template.conf — создайте его сначала (см. macos/README.md)" >&2
    exit 1
fi

BIN="/Library/wg0-nets/wg0-nets-update.sh"
mkdir -p "$(dirname "$BIN")"
curl -fsSL "https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/macos/update-tunnel.sh" -o "$BIN"
chmod +x "$BIN"

PLIST="/Library/LaunchDaemons/com.network-prefixes.wg0-nets-update.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.network-prefixes.wg0-nets-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$REAL_HOME</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>StandardOutPath</key>
    <string>/var/log/wg0-nets-update.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/wg0-nets-update.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST"
chown root:wheel "$PLIST"

launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "Установлено. LaunchDaemon поднят — обновление тоннеля запустится сразу (RunAtLoad) и дальше каждые 6ч."
echo "Ручной запуск: sudo $BIN"
