# Разовая настройка split-tunnel через WireGuard-интерфейс wg2 (RouterOS v7+).
# Идемпотентно — можно запускать повторно, дублей не создаёт.
#
# Установка на роутере:
#   /tool fetch url="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/setup.rsc" dst-path=setup.rsc
#   /import file-name=setup.rsc
#
# Что делает:
#   1. Отдельная routing table "to-wg2" с default route через интерфейс wg2.
#   2. Mangle-правила: пакеты на адреса из address-list "wg2-nets" маркируются
#      для маршрутизации через to-wg2 (и значит через wg2), весь остальной
#      трафик идёт как обычно через основную таблицу.
#   3. Скрипт wg2-nets-update: скачивает mikrotik/wg2-nets.rsc из репозитория
#      и импортирует его (он сам пересобирает address-list "wg2-nets").
#   4. Планировщик: запускает этот скрипт раз в сутки.
#
# ВАЖНО: /system script run выполняет команды из скачанного .rsc с правами
# полного администратора роутера. Это публичный репозиторий под вашим же
# GitHub-аккаунтом (evgen66rus/network-prefixes) — риск в том, что при
# компрометации этого аккаунта злоумышленник получит возможность выполнять
# произвольные команды на роутере при следующем ежедневном обновлении.
# Файл wg2-nets.rsc генерируется только скриптом scripts/fetch.py и содержит
# исключительно address-list add/remove — но раз в сутки полезно проверять,
# что это по-прежнему так (например, через `git log` в репозитории).

:local wgIface "wg2"
:local rtable "to-wg2"
:local addrList "wg2-nets"

# 1. Отдельная routing table для VPN-трафика
:if ([:len [/routing table find where name=$rtable]] = 0) do={
    /routing table add name=$rtable fib
    :log info "wg2-nets: created routing table $rtable"
}

# 2. Дефолтный маршрут в этой таблице через wg2
:if ([:len [/ip route find where routing-table=$rtable and dst-address="0.0.0.0/0" and gateway=$wgIface]] = 0) do={
    /ip route add dst-address=0.0.0.0/0 gateway=$wgIface routing-table=$rtable comment="split-tunnel default via wg2"
    :log info "wg2-nets: created default route via $wgIface in $rtable"
}

# 3. Mangle: маршрутизация по dst-address-list
:if ([:len [/ip firewall mangle find where comment="wg2-nets split-tunnel (prerouting)"]] = 0) do={
    /ip firewall mangle add chain=prerouting dst-address-list=$addrList action=mark-routing new-routing-mark=$rtable passthrough=yes comment="wg2-nets split-tunnel (prerouting)"
    :log info "wg2-nets: added prerouting mangle rule"
}
# chain=output — если трафик к этим адресам может генерировать сам роутер (не обязательно для обычного LAN-форвардинга)
:if ([:len [/ip firewall mangle find where comment="wg2-nets split-tunnel (output)"]] = 0) do={
    /ip firewall mangle add chain=output dst-address-list=$addrList action=mark-routing new-routing-mark=$rtable passthrough=yes comment="wg2-nets split-tunnel (output)"
    :log info "wg2-nets: added output mangle rule"
}

# 4. Скрипт ежедневного обновления address-list из репозитория
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
            :log warning "wg2-nets: update FAILED, address-list not changed"
        }
    }
    :log info "wg2-nets: created update script"
}

# 5. Планировщик — раз в сутки
:if ([:len [/system scheduler find where name="wg2-nets-update"]] = 0) do={
    /system scheduler add name="wg2-nets-update" interval=1d start-time=04:20:00 on-event="/system script run wg2-nets-update"
    :log info "wg2-nets: scheduler created (daily at 04:20)"
}

:log info "wg2-nets: setup done. Run '/system script run wg2-nets-update' once manually to populate the address-list now."
