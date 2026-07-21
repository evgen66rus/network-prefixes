# network-prefixes

IPv4/IPv6-префиксы популярных сервисов для proxy / VPN split-tunnel.

## Файлы

| Файл | Сервис |
|---|---|
| `data/telegram.txt` | Telegram |
| `data/cloudflare.txt` | Cloudflare |
| `data/amazon.txt` | AWS (весь диапазон, не роутится автоматически) |
| `data/microsoft.txt` | Azure/Microsoft (весь диапазон, не роутится автоматически) |
| `data/meta.txt` | Facebook/Instagram/WhatsApp |
| `data/twitter.txt` | Twitter/X |
| `data/netflix.txt` | Netflix |
| `data/youtube_google.txt` | Google + YouTube |
| `data/linkedin.txt` | LinkedIn |
| `data/tiktok.txt` | TikTok |
| `data/railway.txt` | Railway |
| `data/openai.txt` | OpenAI |
| `data/anthropic.txt` | Anthropic (claude.ai) |
| `data/github.txt` | GitHub |
| `data/apple.txt` | Apple (FaceTime/iMessage и весь остальной Apple) |
| `data/discord.txt` | Discord |
| `data/pornhub.txt` | Pornhub / Aylo |
| `data/openai_web.txt` | OpenAI/ChatGPT веб |
| `data/resend.txt` | Resend |
| `data/atakdomain.txt` | atakdomain.com |
| `data/all.txt` | Объединённый список |
| `data/manifest.json` | Какие файлы участвуют в роутинге через MikroTik |

## Обновить локально

```bash
python3 scripts/fetch.py
```

## Автообновление

`.github/workflows/update.yml` — раз в сутки, коммитит изменения.

## MikroTik

См. [`mikrotik/README.md`](mikrotik/README.md).

## Linux (wg0)

См. [`linux/README.md`](linux/README.md).
