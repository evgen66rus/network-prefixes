# network-prefixes

IPv4/IPv6-префиксы популярных сервисов для proxy / VPN split-tunnel (обход блокировок).
Данные генерируются автоматически ([`scripts/fetch.py`](scripts/fetch.py)) из официальных
фидов провайдеров и публичного [RIPEstat](https://stat.ripe.net/) API — руками файлы в
`data/` не редактируются, любые правки перетрёт следующий запуск.

## Что внутри

| Файл | Сервис | Источник |
|---|---|---|
| `data/telegram.txt` | Telegram | [official cidr.txt](https://core.telegram.org/resources/cidr.txt) |
| `data/cloudflare.txt` | Cloudflare | official ips-v4/ips-v6 |
| `data/amazon.txt` | AWS (весь диапазон) | official ip-ranges.json |
| `data/microsoft.txt` | Azure/Microsoft (весь диапазон) | official Service Tags JSON |
| `data/meta.txt` | Facebook/Instagram/WhatsApp | ASN 32934, 63293, 54115 |
| `data/twitter.txt` | Twitter/X | ASN 13414 |
| `data/netflix.txt` | Netflix (+ Open Connect) | ASN 2906, 40027, 55095 |
| `data/youtube_google.txt` | Google + YouTube | ASN 15169, 19527, 36040 |
| `data/linkedin.txt` | LinkedIn | ASN 14413 |
| `data/tiktok.txt` | TikTok | ASN 138699 |
| `data/railway.txt` | Railway (хостинг, включая `stage.dealcrm.app`) | ASN 400940 |
| `data/openai.txt` | OpenAI (см. ограничение ниже) | ASN 401518 |
| `data/anthropic.txt` | Anthropic (claude.ai, api/console.anthropic.com) | ASN 399358 |
| `data/github.txt` | GitHub (github.com, api, raw.githubusercontent.com и т.п.) | ASN 36459 + 185.199.108.0/22 |
| `data/discord.txt` | Discord | DNS resolve (см. ниже) |
| `data/pornhub.txt` | Pornhub / Aylo | DNS resolve (см. ниже) |
| `data/openai_web.txt` | OpenAI/ChatGPT веб-фронтенд | DNS resolve (см. ниже) |
| `data/resend.txt` | Resend | DNS resolve (см. ниже) |
| `data/atakdomain.txt` | atakdomain.com | DNS resolve (см. ниже) |
| `data/domains.txt` | Исходные FQDN для файлов выше (справочно) | — |
| `data/manifest.json` | Машиночитаемый список: какие CIDR-файлы годятся для роутинга через VPN | — |
| `data/all.txt` | Объединённый список всех CIDR-файлов (без `domains.txt`) | — |

Amazon и Microsoft отдают **весь** официальный диапазон облака (не только "сайт"),
т.к. это единственный вариант официального фида для этих провайдеров. Заворачивать
их целиком в VPN-туннель означает пустить туда любой сайт на AWS/Azure — поэтому
в `manifest.json` они помечены `non_routable_cidr_services` и в MikroTik-скрипте
не используются (см. [mikrotik/](mikrotik/README.md)).

`cloudflare.txt` — ровно та же по сути категория (весь anycast-диапазон CDN,
не конкретный сервис), но **сознательно оставлен в `routable_cidr_services`**:
это был явный отдельный пункт в исходном запросе, и, в отличие от amazon/
microsoft, у него всего 22 подсети. Следствие: через `wg2` едет вообще любой
сайт на Cloudflare, а не только перечисленные ниже сервисы — но заодно это
делает нерелевантным "гео-DNS" ограничение для них (см. следующий раздел).

## Сервисы без выделенного ASN: резолв по DNS

Discord, Pornhub/Aylo, веб-фронтенд OpenAI, Resend и atakdomain.com сидят на
общем CDN (в основном Cloudflare) вместе с множеством посторонних сайтов —
своего ASN нет, точный список по IP штатным способом не построить:

- **Discord** — голос/CDN идут через Cloudflare и `i3D.net` (AS49544); i3D — это
  анти-DDoS хостер для игровых серверов множества клиентов, не только Discord.
- **Pornhub / Aylo** — раздаётся через стороннего хостера (Reflected Networks),
  выделенного ASN не найдено.
- **OpenAI / ChatGPT (веб)** — `chatgpt.com` фронтится Cloudflare (общий anycast);
  `data/openai.txt` содержит единственный найденный собственный префикс
  OpenAI (AS401518, `199.47.142.0/23`) — это малая часть их реальной инфраструктуры.
- **Resend, atakdomain.com** — тоже за Cloudflare (проверено `dig`).

Для этих пяти `scripts/fetch.py` резолвит FQDN из `DOMAIN_SERVICES` (A + AAAA)
и пишет результат как обычный CIDR-файл (`/32`, `/128`) — они полноценно
участвуют в маршрутизации через wg2, как и остальные сервисы.

**Ограничение резолва с раннера — на практике не критично.** Формально резолв
идёт раз в сутки с GitHub Actions (обычно US/EU), и IP-адрес CDN может не
совпадать с тем, что резолвит клиент из другой точки мира. Но все пять
сервисов выше сидят за Cloudflare, чей полный диапазон уже маршрутизируется
через `wg2` отдельным правилом (`cloudflare.txt`, см. выше) — то есть **любой**
edge-IP Cloudflare, независимо от того, откуда его резолвили, и так уже
попадает в `wg2`. Отдельные `discord.txt`/`pornhub.txt`/`resend.txt`/
`openai_web.txt`/`atakdomain.txt` в этом смысле избыточны для самой
маршрутизации — они остаются в репозитории для прозрачности (видно, какие
конкретно IP резолвились и когда), а не потому что без них что-то не доедет
до `wg2`.

## Автообновление

`.github/workflows/update.yml` запускает `scripts/fetch.py` по расписанию (раз
в сутки) и коммитит изменения, если данные обновились — провайдеры регулярно
меняют подсети, статичный снапшот быстро устаревает.

## Локальный запуск

```bash
python3 scripts/fetch.py
```

Без внешних зависимостей — только стандартная библиотека Python 3.

## MikroTik split-tunnel (RouterOS)

Готовый скрипт и инструкция для автоматической синхронизации этих списков
в address-list на MikroTik с маршрутизацией через WireGuard-интерфейс —
см. [`mikrotik/README.md`](mikrotik/README.md).
