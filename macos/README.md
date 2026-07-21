# macOS split-tunnel (wg-quick, не GUI-приложение)

Официальное GUI-приложение WireGuard для macOS — sandboxed, его нельзя
обновлять программно. Автоматизация работает через консольный `wg-quick`
(`brew install wireguard-tools`), который периодически переподнимает
туннель со свежим `AllowedIPs` из network-prefixes.

**Если сейчас используется GUI-приложение с тем же ключом — сначала
отключите его туннель**, иначе два клиента с одним приватным ключом
будут конфликтовать на сервере.

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

```bash
curl -fsSL https://raw.githubusercontent.com/evgen66rus/network-prefixes/main/macos/install.sh | sudo bash
```

Ставит `/usr/local/sbin/wg0-nets-update.sh` и LaunchDaemon
(`com.network-prefixes.wg0-nets-update`, каждые 6ч + при загрузке).

## Ручное обновление / первый подъём туннеля

```bash
sudo /usr/local/sbin/wg0-nets-update.sh
```

## Проверка

```bash
sudo wg show wg0
sudo launchctl print system/com.network-prefixes.wg0-nets-update
cat /var/log/wg0-nets-update.log
```

## Откат

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.network-prefixes.wg0-nets-update.plist
sudo rm /Library/LaunchDaemons/com.network-prefixes.wg0-nets-update.plist
sudo wg-quick down ~/.config/wg0-nets/wg0.conf
sudo rm /usr/local/sbin/wg0-nets-update.sh ~/.config/wg0-nets/wg0.conf
```
