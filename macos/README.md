# macOS split-tunnel (wg-quick, не GUI-приложение)

Официальное GUI-приложение WireGuard для macOS — sandboxed, его нельзя
обновлять программно. Автоматизация работает через консольный `wg-quick`
(`brew install wireguard-tools`), который периодически переподнимает
туннель со свежим `AllowedIPs` из network-prefixes.

Если сейчас используется GUI-приложение с тем же ключом — `update-tunnel.sh`
сам остановит его туннель перед подъёмом (через `scutil --nc stop`, это
официальный VPN-сервис macOS, а не убийство процесса), чтобы два клиента
с одним приватным ключом не конфликтовали на сервере.

## Подготовка

Создать `~/.config/wg0-nets/template.conf` (0600, только для владельца) —
ваш обычный конфиг, `AllowedIPs` можно оставить любым, скрипт его перепишет:

```
[Interface]
PrivateKey = ...
Address = 10.8.0.40/24
DNS = 1.1.1.1

[Peer]
PublicKey = ...
PresharedKey = ...
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 0
Endpoint = your.server:51820
```

```bash
mkdir -p ~/.config/wg0-nets && chmod 700 ~/.config/wg0-nets
chmod 600 ~/.config/wg0-nets/template.conf
brew install wireguard-tools
```

## Установка (один раз)

Скачать и запустить **отдельными командами** (не через `curl | sudo bash` и не
через `&&` в одной строке — на некоторых системах это обрывает загрузку):

```bash
curl -fsSL https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/macos/install.sh -o install.sh
```
```bash
sudo bash install.sh
```
```bash
rm install.sh
```

Ставит `/Library/wg0-nets/wg0-nets-update.sh` и LaunchDaemon
(`com.network-prefixes.wg0-nets-update`, каждые 6ч + при загрузке).
`/usr/local/sbin` намеренно не используется — на Apple Silicon это часть
запечатанного системного тома (read-only), запись туда невозможна даже под root.

## Ручное обновление / первый подъём туннеля

```bash
sudo /Library/wg0-nets/wg0-nets-update.sh
```

## Проверка

`wg show wg0` не работает — `wg` не резолвит "дружественные" имена
(это фича только `wg-quick`), нужен реальный `utunN`:

```bash
sudo wg show all
sudo launchctl print system/com.network-prefixes.wg0-nets-update
cat /var/log/wg0-nets-update.log
```

## Почта (Gmail/Yandex/Mail.ru/iCloud SMTP/IMAP/POP3) в обход туннеля

Почтовые серверы часто сидят на тех же IP, что и остальные сервисы того же
провайдера (Google Gmail ↔ YouTube и т.п.) — разделить по широкому диапазону
нельзя. Пробовали через pf `route-to` (правило по порту вместо адреса) —
не сработало: `route-to` не меняет source-адрес, который сокет уже выбрал
по таблице маршрутизации (адрес туннеля), так что пакет всё равно
бесполезен на реальном интернете, даже если физически уйдёт через нужный
интерфейс — подтверждено `tcpdump`.

Вместо этого `update-tunnel.sh` при каждом прогоне резолвит список
хостов (`MAIL_HOSTS` в скрипте) через `dscacheutil` — локально на самом
Маке, не на GitHub Actions, точка зрения именно вашей сети — и добавляет
`/32`-маршруты на эти конкретные IP через реальный шлюз. `/32` всегда
побеждает широкий диапазон туннеля по longest-prefix-match — это решение
ядра, а не pf, source-адрес подбирается правильно сам. Список резолвленных
IP хранится в `~/.config/wg0-nets/mail-routes.txt`; при следующем резолве
маршруты для адресов, которые сервер уже не использует, убираются, для
новых — добавляются.

Сейчас в списке:
- Gmail: `smtp.gmail.com`, `imap.gmail.com`, `pop.gmail.com`
- Yandex: `smtp.yandex.ru`, `imap.yandex.ru`, `pop.yandex.ru`
- Mail.ru: `smtp.mail.ru`, `imap.mail.ru`, `pop.mail.ru`
- iCloud: `smtp.mail.me.com`, `imap.mail.me.com` (POP3 у iCloud Mail
  не существует — `pop.mail.me.com` не резолвится, поэтому не включён)

## Откат

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.network-prefixes.wg0-nets-update.plist
sudo rm /Library/LaunchDaemons/com.network-prefixes.wg0-nets-update.plist
sudo wg-quick down ~/.config/wg0-nets/wg0.conf
while read -r ip; do sudo route -q -n delete -inet "$ip"; done < ~/.config/wg0-nets/mail-routes.txt
sudo rm -rf /Library/wg0-nets ~/.config/wg0-nets/wg0.conf ~/.config/wg0-nets/mail-routes.txt
```
