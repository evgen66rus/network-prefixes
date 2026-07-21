# Linux split-tunnel через wg0

Предполагается: WireGuard-клиент уже настроен на интерфейсе `wg0`, у пира
`AllowedIPs = 0.0.0.0/0, ::/0` и в `[Interface]` стоит `Table = off` (иначе
wg-quick сам управляет маршрутами и будет конфликтовать с этими правилами).

## Установка (один раз, от root)

```bash
curl -fsSL https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/linux/install.sh | sudo bash
sudo /usr/local/sbin/wg0-nets-update.sh
```

Ставит:
- `/usr/local/sbin/wg0-nets-update.sh` — сам синк маршрутов.
- cron `0 4 * * *` — ежедневное обновление.
- cron `@reboot` — ждёт поднятия `wg0` (до 60с) и применяет маршруты после рестарта.

## Ручное обновление

```bash
sudo /usr/local/sbin/wg0-nets-update.sh
```

Если `raw.githubusercontent.com` недоступен — правка URL в скрипте на
jsDelivr-зеркало (`https://cdn.jsdelivr.net/gh/evgen66rus/network-prefixes@main/linux/wg0-routes.txt`).

## Проверка

```bash
ip route show | grep -c wg0
ip -6 route show | grep -c wg0
crontab -l
cat /var/lib/wg0-nets/applied.txt | wc -l
journalctl -t wg0-nets --since today   # или /var/log/syslog, смотря на дистрибутив
```

## Откат

```bash
sudo crontab -l | grep -v wg0-nets | sudo crontab -
while read -r p; do
    [[ "$p" == *:* ]] && sudo ip -6 route del "$p" dev wg0 || sudo ip route del "$p" dev wg0
done < /var/lib/wg0-nets/applied.txt
sudo rm -rf /var/lib/wg0-nets /usr/local/sbin/wg0-nets-update.sh /usr/local/sbin/wg0-nets-wait-and-update.sh
```
