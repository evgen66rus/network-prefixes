# MikroTik split-tunnel через wg2

Автоматическая синхронизация [`data/`](../data) на MikroTik: трафик к адресам
из этого репозитория идёт через WireGuard-интерфейс `wg2`, весь остальной —
как обычно. Проверено для RouterOS **v7** (для v6 понадобится переписать
routing table/mark-routing на старый синтаксис `routing-mark`).

## Как это устроено

- **`../scripts/fetch.py`** генерирует [`wg2-nets.rsc`](wg2-nets.rsc) — готовый
  RouterOS-скрипт, который полностью пересобирает address-list `wg2-nets` из
  "маршрутизируемых" файлов (`manifest.json → routable_cidr_services`) плюс
  `domains.txt`. `amazon.txt`/`microsoft.txt` **не включены** — это весь
  адресный пул AWS/Azure целиком, заворачивать его в VPN означает пустить
  туда любой сайт на этом облаке, а не только нужный сервис.
- Для Discord/Pornhub/OpenAI-веб/Resend/atakdomain.com в `wg2-nets` добавляются
  не IP, а **сами домены** (`address=discord.com` и т.п.) — RouterOS умеет
  резолвить FQDN прямо в address-list и сам держит IP актуальными при смене
  DNS. Плюс: point-in-time резолв не нужен, минус: сработает только для
  DNS-запросов, которые реально идут через резолвер, видимый роутеру.
- **`setup.rsc`** — разовая настройка: routing table `to-wg2` с default route
  через `wg2`, mangle-правила `mark-routing` по `dst-address-list=wg2-nets`,
  плюс сам скрипт обновления и планировщик (раз в сутки, 04:20).

## Установка (один раз)

В терминале MikroTik (Winbox → New Terminal, или по SSH):

```
/tool fetch url="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/setup.rsc" dst-path=setup.rsc
/import file-name=setup.rsc
/system script run wg2-nets-update
```

Третья команда сразу наполняет `wg2-nets` (иначе список будет пустым до
04:20 следующего дня). Дальше обновление идёт само по расписанию.

## Проверка

```
/ip firewall address-list print count-only where list=wg2-nets
/ip route print where routing-table=to-wg2
/ip firewall mangle print where comment~"wg2-nets"
/system scheduler print where name=wg2-nets-update
/log print where topics~"script" and message~"wg2-nets"
```

Проверить, что конкретный хост реально уходит через wg2:

```
/tool traceroute 157.240.1.35 routing-table=to-wg2
```

## Масштаб (hAP ac lite, 64 МБ ОЗУ)

Список "маршрутизируемых" сервисов (без amazon/microsoft) — около 3000
префиксов + 18 доменов. Для hAP ac lite это безопасный объём: address-list
на MikroTik держит на порядок больше записей даже на слабом железе. Если
захотите добавить amazon.txt/microsoft.txt в `wg2-nets` вручную — учтите,
что это ещё ~70 000 записей, и стоит сначала проверить `/system resource
print` (свободная память) перед этим на таком роутере.

## Безопасность

`wg2-nets-update` раз в сутки скачивает `.rsc`-файл из **публичного**
репозитория и выполняет его команды с правами администратора роутера
(`/import`). Файл генерируется только `scripts/fetch.py` и содержит
исключительно `address-list add/remove` — но это означает, что при
компрометации GitHub-аккаунта `evgen66rus` кто-то сможет выполнить
произвольные команды на роутере при следующем обновлении. Приемлемо для
личного роутера при условии, что аккаунт GitHub защищён (2FA и т.п.).

## Если нужно откатить

```
/system scheduler remove [find where name=wg2-nets-update]
/system script remove [find where name=wg2-nets-update]
/ip firewall mangle remove [find where comment~"wg2-nets"]
/ip route remove [find where routing-table=to-wg2]
/routing table remove [find where name=to-wg2]
/ip firewall address-list remove [find where list=wg2-nets]
```
