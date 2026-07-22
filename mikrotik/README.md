# MikroTik split-tunnel через wg2

## Установка (один раз)

```
/tool fetch url="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/setup.rsc" dst-path=setup.rsc
/import file-name=setup.rsc
/system script run wg2-nets-update
```

## Ручное обновление

```
/system script run wg2-nets-update
```

Если `raw.githubusercontent.com` недоступен — через jsDelivr:

```
/tool fetch url="https://cdn.jsdelivr.net/gh/evgen66rus/network-prefixes@main/mikrotik/wg2-nets.rsc" dst-path=wg2-nets-fetched.rsc
/import file-name=wg2-nets-fetched.rsc
/file remove [/file find where name=wg2-nets-fetched.rsc]
```

## Проверка

```
/ip route print where comment~"src:"
/ipv6 route print where comment~"src:"
/system scheduler print where name=wg2-nets-update
/log print where topics~"script" and message~"wg2-nets"
```

## Почта (SMTP/IMAP/POP3) в обход wg2

Статические маршруты не смотрят на порт, поэтому для почты — отдельная
policy routing: mangle помечает TCP-трафик на порты 25/465/587 (SMTP),
110/995 (POP3), 143/993 (IMAP) для маршрутизации через routing table
`to-isp`, в которой лежит только обычный маршрут через реальный ISP-шлюз
(без специфичных маршрутов через wg2 — тех нет в `to-isp`, они только в
`main`). Поэтому для помеченного трафика поиск маршрута никогда не видит
wg2, независимо от IP назначения — в отличие от подхода по конкретным
адресам (как на macOS), тут неважно, какой именно почтовый провайдер.

Проверка, что правило реально матчит трафик (счётчики растут при попытке
подключения на один из портов) **и** что оно реально влияет на маршрутизацию:
```
/ip firewall mangle print stats where comment~"mailbypass"
/ip route print where routing-table=to-isp
/routing rule print
```
Последняя команда критична: mangle только помечает пакет (`new-routing-mark`),
но без `/routing rule`, связывающего эту метку с таблицей `to-isp`, поиск
маршрута всё равно идёт по `main` — счётчик в mangle растёт, а трафик
по-прежнему уходит через wg2. Убедились в этом вживую: пустой
`/routing rule print` при рабочем mangle — трафик шёл в туннель.

## Откат

```
/system scheduler remove [find where name=wg2-nets-update]
/system script remove [find where name=wg2-nets-update]
/ip route remove [find where comment~"src:"]
/ipv6 route remove [find where comment~"src:"]
/ip firewall mangle remove [find where comment~"wg2-nets: mailbypass"]
/routing rule remove [find where table=to-isp]
/ip route remove [find where routing-table=to-isp]
/routing table remove [find where name=to-isp]
```
