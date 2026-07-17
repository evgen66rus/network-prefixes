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
| `data/all.txt` | Объединённый список всех файлов выше | — |

Amazon и Microsoft отдают **весь** официальный диапазон облака (не только "сайт"),
т.к. это единственный вариант официального фида для этих провайдеров.

## Важное ограничение: сервисы на общей инфраструктуре

Часть запрошенных сервисов **не имеет** отдельного файла, потому что у них нет
своего выделенного ASN — они целиком отдаются через сторонний CDN/хостинг,
общий с множеством не относящихся к делу сайтов. Список по IP для них either
неполный, либо ловит чужой трафик:

- **Discord** — голос/CDN идут через Cloudflare и `i3D.net` (AS49544); i3D — это
  анти-DDoS хостер для игровых серверов множества клиентов, не только Discord.
- **Pornhub / Aylo** — раздаётся через стороннего хостера (Reflected Networks),
  выделенного ASN не найдено.
- **OpenAI / ChatGPT (веб)** — `chatgpt.com` фронтится Cloudflare (общий anycast);
  `data/openai.txt` содержит единственный найденный собственный префикс
  OpenAI (AS401518, `199.47.142.0/23`) — это малая часть их реальной инфраструктуры.

**Для этих сервисов используйте маршрутизацию по домену (SNI/DNS-based rules)**
в вашем прокси/VPN-клиенте (sing-box, Xray, Clash и т.п.), а не по IP — это
стандартная практика для CDN-based ресурсов и она гораздо надёжнее.

## Автообновление

`.github/workflows/update.yml` запускает `scripts/fetch.py` по расписанию (раз
в сутки) и коммитит изменения, если данные обновились — провайдеры регулярно
меняют подсети, статичный снапшот быстро устаревает.

## Локальный запуск

```bash
python3 scripts/fetch.py
```

Без внешних зависимостей — только стандартная библиотека Python 3.
