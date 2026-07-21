#!/usr/bin/env bash
# Синхронизирует статические маршруты через WireGuard-интерфейс wg0 из
# network-prefixes (linux/wg0-routes.txt). Полный ресинк: удаляет маршруты,
# которых больше нет в списке, добавляет/обновляет актуальные. Требует root
# (ip route) и записывает состояние в $STATE_FILE для последующего diff.
set -euo pipefail

IFACE="wg0"
URL_PRIMARY="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/linux/wg0-routes.txt"
URL_FALLBACK="https://cdn.jsdelivr.net/gh/evgen66rus/network-prefixes@main/linux/wg0-routes.txt"
STATE_DIR="/var/lib/wg0-nets"
STATE_FILE="$STATE_DIR/applied.txt"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

if ! curl -fsSL "$URL_PRIMARY" -o "$TMP_FILE"; then
    echo "primary URL failed, trying jsDelivr fallback" >&2
    curl -fsSL "$URL_FALLBACK" -o "$TMP_FILE"
fi

grep -v '^#' "$TMP_FILE" | grep -v '^[[:space:]]*$' | sort -u -o "$TMP_FILE"
sort -u "$STATE_FILE" -o "$STATE_FILE"

# в state, но не в новом списке — удалить
comm -23 "$STATE_FILE" "$TMP_FILE" | while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    if [[ "$prefix" == *:* ]]; then
        ip -6 route del "$prefix" dev "$IFACE" 2>/dev/null || true
    else
        ip route del "$prefix" dev "$IFACE" 2>/dev/null || true
    fi
done

# весь новый список — добавить/обновить
while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    if [[ "$prefix" == *:* ]]; then
        ip -6 route replace "$prefix" dev "$IFACE"
    else
        ip route replace "$prefix" dev "$IFACE"
    fi
done < "$TMP_FILE"

cp "$TMP_FILE" "$STATE_FILE"
logger -t wg0-nets "updated $(wc -l < "$STATE_FILE") routes via $IFACE" 2>/dev/null || true
