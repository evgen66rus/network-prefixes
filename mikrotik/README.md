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

## Откат

```
/system scheduler remove [find where name=wg2-nets-update]
/system script remove [find where name=wg2-nets-update]
/ip route remove [find where comment~"src:"]
/ipv6 route remove [find where comment~"src:"]
```
