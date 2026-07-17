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
# Никакой отдельной routing table / mangle не нужно — маршруты обычные,
# статические, как /ip route add gateway=wg2 dst-address=X.
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

:log info "wg2-nets: setup done. Run '/system script run wg2-nets-update' once manually to populate the routes now."
