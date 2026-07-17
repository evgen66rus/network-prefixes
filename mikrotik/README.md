# MikroTik split-tunnel через wg2

Автоматическая синхронизация [`data/`](../data) на MikroTik: для каждого
сервиса — обычные статические маршруты `gateway=wg2`, весь остальной трафик
идёт как обычно. Проверено для RouterOS **v7**.

## Как это устроено

- **`../scripts/fetch.py`** генерирует [`wg2-nets.rsc`](wg2-nets.rsc) — готовый
  RouterOS-скрипт со статическими маршрутами вида:
  ```
  /ip route add dst-address="157.240.1.0/24" gateway=wg2 comment="src:meta"
  ```
  Каждая группа (сервис) сначала полностью удаляется по `comment=src:<service>`,
  затем добавляется заново из актуальных данных — так скрипт сам решает
  add/remove при каждом запуске, без diff-логики внутри RouterOS.
- IPv4 и IPv6 — разные меню (`/ip route` и `/ipv6 route` соответственно),
  скрипт разруливает это сам по формату префикса.
- Список сервисов — `manifest.json → routable_cidr_services`. `amazon.txt`/
  `microsoft.txt` **не включены** — это весь адресный пул AWS/Azure целиком,
  заворачивать его в VPN означает пустить туда любой сайт на этом облаке.
- **`data/domains.txt`** (Discord/Pornhub/OpenAI-веб/Resend/atakdomain.com)
  в `wg2-nets.rsc` **не входит** — статическому маршруту нужен конкретный
  CIDR, а не имя домена. Для этих сервисов нужен отдельный механизм
  (address-list с FQDN + policy routing через mangle) — в прошлой версии
  этого README он был описан, но не завёлся на практике; пока не встроен
  в автообновление. Можно добавить руками при необходимости:
  ```
  /ip firewall address-list add list=wg2-domains address=discord.com
  ```
  и промаршрутизировать этот address-list отдельно, когда понадобится.

## Установка (один раз)

В терминале MikroTik (Winbox → New Terminal, или по SSH):

```
/tool fetch url="https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/mikrotik/setup.rsc" dst-path=setup.rsc
/import file-name=setup.rsc
/system script run wg2-nets-update
```

Третья команда сразу наполняет маршруты (иначе список будет пустым до
04:20 следующего дня). Дальше обновление идёт само по расписанию.

## Ручное обновление в любой момент

```
/system script run wg2-nets-update
```

Если `raw.githubusercontent.com` недоступен (SSL-хендшейк зависает,
типичный симптом DPI-блокировки самого GitHub) — одноразовый обход через
jsDelivr (зеркалит raw-файлы GitHub):

```
/tool fetch url="https://cdn.jsdelivr.net/gh/evgen66rus/network-prefixes@main/mikrotik/wg2-nets.rsc" dst-path=wg2-nets-fetched.rsc
/import file-name=wg2-nets-fetched.rsc
/file remove [/file find where name=wg2-nets-fetched.rsc]
```
Если это стабильно нужно — поменяйте URL внутри `wg2-nets-update`
(`/system script edit wg2-nets-update source`) на jsDelivr насовсем.

## Проверка

```
/ip route print where comment~"src:"
/ipv6 route print where comment~"src:"
/ip route print count-only where comment~"src:"
/system scheduler print where name=wg2-nets-update
/log print where topics~"script" and message~"wg2-nets"
```

Проверить, что конкретный адрес реально маршрутизируется через wg2:

```
/ip route get [/ip route find where dst-address="157.240.1.0/24"] gateway
```

Версионно-независимая проверка живого трафика — счётчики самого маршрута
не считаются в RouterOS, поэтому лучше смотреть по `/ip firewall connection
print` для активного соединения к нужному адресу, либо просто `/ping <ip>`
и `/tool traceroute <ip>` без дополнительных параметров — раз маршрут
статический и более специфичный, чем default, он применится автоматически.

## Масштаб (hAP ac lite, 64 МБ ОЗУ)

"Маршрутизируемые" сервисы (без amazon/microsoft) — около 3100 маршрутов
(включая GitHub). Для hAP ac lite это безопасный объём — RouterOS штатно
работает с многими тысячами статических маршрутов даже на слабом железе.
Полные диапазоны amazon.txt/microsoft.txt (~70 000 записей) добавлять как
маршруты не стоит — проверьте `/system resource print` перед этим, если
всё же понадобится.

## Безопасность

`wg2-nets-update` раз в сутки скачивает `.rsc`-файл из **публичного**
репозитория и выполняет его команды с правами администратора роутера
(`/import`). Файл генерируется только `scripts/fetch.py` и содержит
исключительно `/ip route`/`/ipv6 route` add/remove — но это означает, что
при компрометации GitHub-аккаунта `evgen66rus` кто-то сможет выполнить
произвольные команды на роутере при следующем обновлении. Приемлемо для
личного роутера при условии, что аккаунт GitHub защищён (2FA и т.п.).

## Если нужно откатить

```
/system scheduler remove [find where name=wg2-nets-update]
/system script remove [find where name=wg2-nets-update]
/ip route remove [find where comment~"src:"]
/ipv6 route remove [find where comment~"src:"]
```
