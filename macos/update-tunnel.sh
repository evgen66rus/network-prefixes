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
MAIL_PORTS="25 465 587 110 995 143 993"  # SMTP/SMTPS/Submission, POP3/POP3S, IMAP/IMAPS
PF_ANCHOR="wg0-nets-mailbypass"
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

# `|| true` — та же ловушка pipefail: если после фильтрации не останется ни
# одной строки, grep вернёт 1 и убьёт скрипт здесь же, до проверки ниже.
ALLOWED="$(grep -v '^#' "$TMP_PREFIXES" | grep -v '^[[:space:]]*$' | paste -sd, - || true)"
if [ -z "$ALLOWED" ]; then
    echo "Пустой список префиксов, ничего не меняю" >&2
    exit 1
fi

awk -v allowed="$ALLOWED" '
    /^[[:space:]]*AllowedIPs/ { print "AllowedIPs = " allowed; next }
    { print }
' "$TEMPLATE" > "$TMP_CONF"

# Ищем СВОИ интерфейсы по peer public key (а не по имени "wg0" — internal
# name-mapping wg-quick может разойтись с тем, что видит `wg show`, это уже
# наблюдалось на практике). Однозначно наш туннель, не трогает чужие VPN.
OUR_PEER_KEY="$(grep -m1 '^PublicKey' "$TEMPLATE" | awk '{print $3}' || true)"

find_our_ifaces() {
    wg show all 2>/dev/null | awk -v key="$OUR_PEER_KEY" '
        /^interface:/ { iface = $2 }
        $1 == "peer:" && $2 == key { print iface }
    '
}

# Никакого "пропустить, если не изменилось": именно эта оптимизация чаще
# всего застревала — find_our_ifaces видит зависший интерфейс от прошлого
# сбоя, считает "уже всё ок" и выходит, даже не запуская очистку ниже.
# Полный цикл down+cleanup+up занимает секунды, гоняется редко (раз в 6ч
# или вручную) — упрощение того не стоит.
install -m 600 "$TMP_CONF" "$ACTIVE_CONF"

# GUI-приложение WireGuard регистрирует свой туннель как обычный VPN-сервис
# (NEVPNManager, bundle id com.wireguard.macos) — если он сейчас Connected,
# он использует тот же ключ/адрес, что и наш wg-quick-туннель, и будет с ним
# конфликтовать. Останавливаем через scutil --nc, а не убийством процесса.
# Его собственный utun (сандбоксированный, отдельный control-plane) сюда не
# входит — find_our_ifaces видит только интерфейсы, поднятые через wg-quick.
# `|| true` в конце всего пайплайна обязателен: если GUI-туннель сейчас
# Disconnected, "grep (Connected)" не находит строк и возвращает код 1 —
# с pipefail это код выхода всего пайплайна, и set -e молча убивал скрипт
# именно тут (не найдено — не ошибка, но выглядело как полный сбой).
scutil --nc list 2>/dev/null | grep "com.wireguard.macos" | grep "(Connected)" | awk '{print $3}' | while IFS= read -r uuid; do
    [ -z "$uuid" ] && continue
    echo "Останавливаю GUI-туннель WireGuard ($uuid)" >&2
    scutil --nc stop "$uuid" >/dev/null 2>&1 || true
done || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    scutil --nc list 2>/dev/null | grep "com.wireguard.macos" | grep -q "(Connected)" || break
    sleep 1
done

cleanup_stale_ifaces() {
    find_our_ifaces | while IFS= read -r stale_iface; do
        [ -z "$stale_iface" ] && continue
        echo "Убираю зависший интерфейс $stale_iface" >&2
        ifconfig "$stale_iface" destroy 2>/dev/null || true
    done
}

# Штатный путь: down по своему же конфигу — это находит name-mapping wg0->utunN,
# даже если "wg show wg0" его почему-то не видит (та самая нестыковка выше).
# Вывод не глушим — если down реально не отработал, это должно быть видно.
wg-quick down "$ACTIVE_CONF" || true

# Пауза: `wg-quick down` убирает control-сокет и name-mapping файл, но сам
# utun-девайс освобождается чуть позже (гонка) — без паузы следующий `up`
# иногда натыкается на ещё не до конца снятый интерфейс ("already exists").
sleep 2
cleanup_stale_ifaces
sleep 1

if ! wg-quick up "$ACTIVE_CONF"; then
    echo "wg-quick up не удался с первой попытки, доп. очистка и повтор" >&2
    cleanup_stale_ifaces
    sleep 2
    wg-quick up "$ACTIVE_CONF"
fi

# Почта (SMTP/IMAP/POP3) — в обход туннеля независимо от IP, портовое правило
# в отдельном pf-anchor (не трогает /etc/pf.conf и чужие anchors вроде
# cisco.anyconnect.vpn). AllowedIPs у нас не 0.0.0.0/0, так что настоящий
# default gateway/interface не подменяется wg-quick и виден напрямую.
GW="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')"
PHYS_IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
if [ -n "$GW" ] && [ -n "$PHYS_IFACE" ]; then
    pfctl -e 2>/dev/null || true  # ref-counted; ошибка "already enabled" не страшна
    # `pfctl -f -` всегда предупреждает про возможный flush главного ruleset —
    # это безобидно (проверено: cisco.anyconnect.vpn/com.apple остаются на месте),
    # но раньше скрипт глушил вообще любую ошибку через `|| true` и врал об успехе.
    # Теперь фильтруем именно это известное предупреждение и проверяем результат
    # по факту через pfctl -s Anchors, а не по exit code.
    printf 'pass out quick route-to (%s %s) proto tcp to any port { %s }\n' "$PHYS_IFACE" "$GW" "$MAIL_PORTS" \
        | pfctl -a "$PF_ANCHOR" -f - 2>&1 \
        | grep -Ev '^(No ALTQ|ALTQ related|pfctl: Use of -f|present in the main|See /etc/pf\.conf)|^$' >&2 || true
    if pfctl -s Anchors 2>/dev/null | grep -qx "$PF_ANCHOR"; then
        echo "PF: почта ($MAIL_PORTS) идёт через $PHYS_IFACE/$GW в обход туннеля"
    else
        echo "PF: anchor $PF_ANCHOR не создался — mail-bypass НЕ применён" >&2
    fi
else
    echo "Не удалось определить default gateway/interface — mail-bypass PF правило не применено" >&2
fi

echo "OK: tunnel resynced, $(wc -l < "$TMP_PREFIXES") prefixes"
logger -t wg0-nets "tunnel $IFACE resynced, $(wc -l < "$TMP_PREFIXES") prefixes" 2>/dev/null || true
