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

# "wg show wg0" ненадёжен как проверка "туннель поднят" на macOS: у wg-quick
# свой internal name-mapping (wg0 -> utunN), который может разойтись с тем,
# что видит `wg show` (наблюдалось на практике: wg show wg0 не находил
# интерфейс, а wg-quick up тут же падал с "wg0 already exists as utunN").
# Поэтому ищем СВОИ интерфейсы по peer public key — это однозначно наш
# туннель, независимо от имени/номера utun, и не трогает чужие VPN на машине.
OUR_PEER_KEY="$(grep -m1 '^PublicKey' "$TEMPLATE" | awk '{print $3}')"

find_our_ifaces() {
    wg show all 2>/dev/null | awk -v key="$OUR_PEER_KEY" '
        /^interface:/ { iface = $2 }
        $1 == "peer:" && $2 == key { print iface }
    '
}

if [ -f "$ACTIVE_CONF" ] && diff -q "$TMP_CONF" "$ACTIVE_CONF" >/dev/null 2>&1 && [ -n "$(find_our_ifaces)" ]; then
    exit 0  # конфиг не изменился и туннель уже поднят
fi

install -m 600 "$TMP_CONF" "$ACTIVE_CONF"

# GUI-приложение WireGuard регистрирует свой туннель как обычный VPN-сервис
# (NEVPNManager, bundle id com.wireguard.macos) — если он сейчас Connected,
# он использует тот же ключ/адрес, что и наш wg-quick-туннель, и будет с ним
# конфликтовать. Останавливаем через scutil --nc, а не убийством процесса.
# Его собственный utun (сандбоксированный, отдельный control-plane) сюда не
# входит — find_our_ifaces видит только интерфейсы, поднятые через wg-quick.
scutil --nc list 2>/dev/null | grep "com.wireguard.macos" | grep "(Connected)" | awk '{print $3}' | while IFS= read -r uuid; do
    [ -z "$uuid" ] && continue
    echo "Останавливаю GUI-туннель WireGuard ($uuid)" >&2
    scutil --nc stop "$uuid" >/dev/null 2>&1 || true
done
for _ in 1 2 3 4 5 6 7 8 9 10; do
    scutil --nc list 2>/dev/null | grep "com.wireguard.macos" | grep -q "(Connected)" || break
    sleep 1
done

# Штатный путь: down по своему же конфигу — это находит name-mapping wg0->utunN,
# даже если "wg show wg0" его почему-то не видит (та самая нестыковка выше).
wg-quick down "$ACTIVE_CONF" >/dev/null 2>&1 || true

# Подчистка: если после этого остались висящие интерфейсы с НАШИМ peer key
# (например, от прошлых прогонов, упавших ДО того, как down успевал отработать) —
# сносим их напрямую. Точечно по ключу, поэтому чужие VPN/utun не задевает.
find_our_ifaces | while IFS= read -r stale_iface; do
    [ -z "$stale_iface" ] && continue
    echo "Убираю зависший интерфейс $stale_iface" >&2
    ifconfig "$stale_iface" destroy 2>/dev/null || true
done

wg-quick up "$ACTIVE_CONF"

logger -t wg0-nets "tunnel $IFACE resynced, $(wc -l < "$TMP_PREFIXES") prefixes" 2>/dev/null || true
