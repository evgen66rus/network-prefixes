#!/usr/bin/env bash
# Разовая установка (запускать от root): кладёт update-routes.sh в
# /usr/local/sbin, ставит cron на ежедневное обновление и на @reboot —
# с ожиданием, пока интерфейс wg0 поднимется.
set -euo pipefail

REPO_RAW_DIR="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/linux"
BIN="/usr/local/sbin/wg0-nets-update.sh"
WAIT_BIN="/usr/local/sbin/wg0-nets-wait-and-update.sh"

curl -fsSL "$REPO_RAW_DIR/update-routes.sh" -o "$BIN"
chmod +x "$BIN"

cat > "$WAIT_BIN" <<'EOF'
#!/usr/bin/env bash
# Ждёт, пока интерфейс wg0 поднимется после ребута, затем запускает update.
for i in $(seq 1 60); do
    if ip addr show dev wg0 2>/dev/null | grep -q "inet "; then
        /usr/local/sbin/wg0-nets-update.sh
        exit 0
    fi
    sleep 1
done
logger -t wg0-nets "wg0 не поднялся за 60с, маршруты не применены"
EOF
chmod +x "$WAIT_BIN"

( crontab -l 2>/dev/null | grep -v wg0-nets-update.sh ; echo "0 4 * * * $BIN" ) | crontab -
( crontab -l 2>/dev/null | grep -v wg0-nets-wait-and-update.sh ; echo "@reboot $WAIT_BIN" ) | crontab -

echo "Установлено. Применить маршруты прямо сейчас: sudo $BIN"
