#!/usr/bin/env bash
# Синхронизирует AllowedIPs туннеля wg0 (wg-quick, не GUI-приложение WireGuard)
# со списком network-prefixes. Секретный шаблон (ключи) лежит ЛОКАЛЬНО вне
# этого репозитория — см. TEMPLATE ниже. Требует root (wg-quick).
set -euo pipefail

# launchd запускает с минимальным PATH, где нет /opt/homebrew/bin (Apple Silicon)
# или /usr/local/bin (Intel) — без этого wg/wg-quick "command not found".
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

TEMPLATE="$HOME/.config/wg0-nets/template.conf"
ACTIVE_CONF="$HOME/.config/wg0-nets/wg0.conf"
IFACE="wg0"
URL_PRIMARY="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/linux/wg0-routes.txt"
URL_FALLBACK="https://cdn.jsdelivr.net/gh/evgen66rus/network-prefixes@main/linux/wg0-routes.txt"

if [ ! -f "$TEMPLATE" ]; then
    echo "Нет шаблона $TEMPLATE — см. macos/README.md" >&2
    exit 1
fi

TMP_PREFIXES="$(mktemp)"
TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_PREFIXES" "$TMP_CONF"' EXIT

if ! curl -fsSL "$URL_PRIMARY" -o "$TMP_PREFIXES"; then
    echo "primary URL failed, trying jsDelivr fallback" >&2
    curl -fsSL "$URL_FALLBACK" -o "$TMP_PREFIXES"
fi

ALLOWED="$(grep -v '^#' "$TMP_PREFIXES" | grep -v '^[[:space:]]*$' | paste -sd, -)"
if [ -z "$ALLOWED" ]; then
    echo "Пустой список префиксов, ничего не меняю" >&2
    exit 1
fi

awk -v allowed="$ALLOWED" '
    /^[[:space:]]*AllowedIPs/ { print "AllowedIPs = " allowed; next }
    { print }
' "$TEMPLATE" > "$TMP_CONF"

if [ -f "$ACTIVE_CONF" ] && diff -q "$TMP_CONF" "$ACTIVE_CONF" >/dev/null 2>&1 && wg show "$IFACE" >/dev/null 2>&1; then
    exit 0  # конфиг не изменился и туннель уже поднят
fi

install -m 600 "$TMP_CONF" "$ACTIVE_CONF"

if wg show "$IFACE" >/dev/null 2>&1; then
    wg-quick down "$ACTIVE_CONF" || true
fi
wg-quick up "$ACTIVE_CONF"

logger -t wg0-nets "tunnel $IFACE resynced, $(wc -l < "$TMP_PREFIXES") prefixes" 2>/dev/null || true
