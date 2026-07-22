# Разовая настройка автообновления статических маршрутов через wg2 (RouterOS v7+).
# Идемпотентно — можно запускать повторно, дублей не создаёт.
#
# Установка на роутере:
#   /tool fetch url="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/setup.rsc" dst-path=setup.rsc
#   /import file-name=setup.rsc
#   /system script run wg2-nets-update
#
# Что делает:
#   1. Создаёт скрипт wg2-nets-update: скачивает mikrotik/wg2-nets.rsc из
#      репозитория и импортирует его — тот сам полностью пересобирает
#      статические маршруты (/ip route, /ipv6 route) с gateway=wg2 и
#      comment=src:<service> (удаляет старые записи группы, добавляет свежие).
#   2. Планировщик: запускает этот скрипт раз в сутки.
#
#   3. Почта (SMTP/IMAP/POP3) в обход wg2 по портам — отдельная routing table
#      "to-isp" (только обычный шлюз) + mangle mark-routing по dst-port.
#      Основные маршруты (п.1) остаются простыми статическими, без mangle.
#
# ВАЖНО: скрипт выполняет команды из скачанного .rsc с правами полного
# администратора роутера. Это публичный репозиторий под вашим GitHub-
# аккаунтом (evgen66rus/network-prefixes) — при компрометации аккаунта
# кто-то сможет выполнить произвольные команды на роутере при следующем
# ежедневном обновлении. wg2-nets.rsc генерируется только scripts/fetch.py
# и содержит исключительно /ip route и /ipv6 route add/remove.

:if ([:len [/system script find where name="wg2-nets-update"]] = 0) do={
    /system script add name="wg2-nets-update" policy=read,write,test source={
        :local url "https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/wg2-nets.rsc"
        :local fname "wg2-nets-fetched.rsc"
        :do {
            /tool fetch url=$url dst-path=$fname check-certificate=yes
            :delay 2s
            /import file-name=$fname
            /file remove [/file find where name=$fname]
            :log info "wg2-nets: update OK"
        } on-error={
            :log warning "wg2-nets: update FAILED, routes not changed"
        }
    }
    :log info "wg2-nets: created update script"
}

:if ([:len [/system scheduler find where name="wg2-nets-update"]] = 0) do={
    /system scheduler add name="wg2-nets-update" interval=1d start-time=04:20:00 on-event="/system script run wg2-nets-update"
    :log info "wg2-nets: scheduler created (daily at 04:20)"
}

# --- Почта (SMTP/IMAP/POP3) в обход wg2, по портам, а не по адресу ---
# Статические маршруты (выше) не умеют смотреть на порт — для этого нужна
# policy routing: mangle помечает трафик по dst-port, отдельная routing table
# "to-isp" содержит ТОЛЬКО обычный маршрут через настоящий ISP-шлюз (без
# specific-маршрутов через wg2, которые лежат в main) — значит для помеченного
# трафика поиск маршрута никогда не увидит wg2, независимо от IP назначения.
:local mailPorts "25,465,587,110,995,143,993"
:local rtable "to-isp"

:if ([:len [/routing table find where name=$rtable]] = 0) do={
    /routing table add name=$rtable fib
    :log info "wg2-nets: created routing table $rtable"
}

:if ([:len [/ip route find where routing-table=$rtable and dst-address="0.0.0.0/0"]] = 0) do={
    :local ispGwId [:pick [/ip route find where dst-address="0.0.0.0/0" and routing-table="main"] 0]
    :local ispGw [/ip route get $ispGwId gateway]
    /ip route add dst-address=0.0.0.0/0 gateway=$ispGw routing-table=$rtable comment="wg2-nets: mailbypass default via ISP"
    :log info "wg2-nets: default route via $ispGw added to $rtable"
}

:if ([:len [/ip firewall mangle find where comment="wg2-nets: mailbypass"]] = 0) do={
    /ip firewall mangle add chain=prerouting protocol=tcp dst-port=$mailPorts action=mark-routing new-routing-mark=$rtable passthrough=yes comment="wg2-nets: mailbypass"
    /ip firewall mangle add chain=output protocol=tcp dst-port=$mailPorts action=mark-routing new-routing-mark=$rtable passthrough=yes comment="wg2-nets: mailbypass"
    :log info "wg2-nets: mailbypass mangle rules added"
}

# Без этого правила routing-mark, выставленный mangle'ом, ни на что не влияет —
# пакет помечается (счётчик в mangle растёт), но реальный поиск маршрута всё
# равно идёт по main, где для многих адресов есть более специфичный маршрут
# через wg2, который и побеждает. Подтверждено вживую: /routing rule print
# был пуст, и почта продолжала уходить в туннель несмотря на рабочий mangle.
:if ([:len [/routing rule find where table=$rtable]] = 0) do={
    /routing rule add action=lookup-only-in-table table=$rtable routing-mark=$rtable
    :log info "wg2-nets: routing rule added for $rtable"
}

:log info "wg2-nets: setup done. Run '/system script run wg2-nets-update' once manually to populate the routes now."
