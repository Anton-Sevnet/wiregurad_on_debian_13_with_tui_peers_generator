# Инструкция по установке WireGuard Server на Debian 13 Trixie

## Системные требования

- Debian 13 Trixie
- Статический IP: 80.233.165.55
- Права root (работаем от root)
- Минимум 512 MB RAM
- Минимум 1 GB свободного места на диске

## Шаг 1: Обновление системы

```bash
apt update
apt upgrade -y
```

## Шаг 2: Установка WireGuard и iptables

```bash
apt install wireguard wireguard-tools iptables iptables-persistent -y
```

**Примечание:** Если планируете использовать DNS в конфигурации WireGuard на сервере, установите также:
```bash
apt install resolvconf -y
# или
apt install openresolv -y
```

Обычно DNS на сервере не нужен - DNS указывается в конфигурации клиента.

## Шаг 3: Включение IP forwarding

```bash
# Временно включить IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Постоянно включить IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
```

## Шаг 4: Настройка файрвола (iptables)

```bash
# Очистить существующие правила (осторожно!)
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Установить политику по умолчанию
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Разрешить loopback интерфейс
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Разрешить установленные соединения
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Разрешить SSH (важно сделать первым!)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Разрешить WireGuard порт (по умолчанию 51820/UDP)
iptables -A INPUT -p udp --dport 51820 -j ACCEPT

# Разрешить пересылку пакетов через WireGuard интерфейс
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT

# Сохранить правила iptables
iptables-save > /etc/iptables/rules.v4

# Проверить правила
iptables -L -n -v
```

## Шаг 5: Генерация ключей сервера

```bash
# Создать директорию для конфигурации
mkdir -p /etc/wireguard
cd /etc/wireguard

# Сгенерировать приватный ключ сервера
wg genkey | tee server_private.key | wg pubkey | tee server_public.key

# Установить правильные права доступа
chmod 600 server_private.key
chmod 644 server_public.key
```

## Шаг 6: Создание конфигурации сервера

Сначала получите приватный ключ сервера:

```bash
# Просмотреть приватный ключ сервера
cat /etc/wireguard/server_private.key
```

Создайте файл `/etc/wireguard/wg0.conf`:

```bash
nano /etc/wireguard/wg0.conf
```

Вставьте следующую конфигурацию, заменив `<SERVER_PRIVATE_KEY>` на содержимое файла `server_private.key` (скопируйте весь ключ, включая знак `=` в конце):

```
[Interface]
# Приватный ключ сервера (вставьте содержимое файла server_private.key)
PrivateKey = <SERVER_PRIVATE_KEY>

# IP адрес интерфейса WireGuard (выберите подсеть, не конфликтующую с вашей сетью)
Address = 10.0.0.1/24

# Порт для прослушивания
ListenPort = 51820

# Команда для настройки NAT (PostUp/PostDown)
# Замените eth0 на имя вашего сетевого интерфейса
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# DNS сервер (опционально, только если нужен DNS на сервере)
# ВАЖНО: Если указываете DNS, установите resolvconf или openresolv
# DNS = 8.8.8.8, 8.8.4.4
```

**Важно:** 
- **НЕ используйте путь к файлу** (`/etc/wireguard/server_private.key`) - вставляйте сам ключ!
- Пример правильного формата: `PrivateKey = SHtbN2D9LhDEf/TKPb3YN761TRke/NB9cuzMw+b7vEQ=`
- Замените `eth0` на имя вашего сетевого интерфейса (проверьте командой `ip addr`)
- Если используете другой сетевой интерфейс, замените `eth0` на правильное имя
- **DNS на сервере обычно не нужен** - DNS указывается в конфигурации клиента. Если не используете DNS на сервере, закомментируйте или удалите строку `DNS`

**Быстрый способ создания конфигурации:**

```bash
# Автоматически создать конфигурацию с приватным ключом
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/server_private.key)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# Затем отредактируйте файл, чтобы заменить eth0 на правильный интерфейс
nano /etc/wireguard/wg0.conf
```

## Шаг 7: Определение сетевого интерфейса

```bash
# Проверить сетевые интерфейсы
ip addr show

# Или
ip link show
```

Найдите интерфейс с IP адресом 80.233.165.55 и используйте его имя в конфигурации вместо `eth0`.

## Шаг 8: Запуск WireGuard

```bash
# Запустить WireGuard интерфейс
wg-quick up wg0

# Проверить статус
wg show

# Включить автозапуск при загрузке системы
systemctl enable wg-quick@wg0
```

## Шаг 9: Проверка работы

```bash
# Проверить статус интерфейса
wg show wg0

# Проверить что интерфейс поднят
ip addr show wg0

# Проверить логи
journalctl -u wg-quick@wg0 -f

# Проверить правила iptables
iptables -L -n -v
iptables -t nat -L -n -v
```

## Шаг 10: Добавление клиентов

Для каждого клиента выполните:

```bash
# Сгенерировать ключи для клиента
cd /etc/wireguard
wg genkey | tee client1_private.key | wg pubkey | tee client1_public.key

# Просмотреть публичный ключ клиента (нужен для добавления в конфигурацию сервера)
cat client1_public.key
```

Добавьте клиента в конфигурацию сервера:

```bash
nano /etc/wireguard/wg0.conf
```

Добавьте в конец файла `/etc/wireguard/wg0.conf` (замените `<CLIENT_PUBLIC_KEY>` на содержимое файла `client1_public.key`):

```
[Peer]
# Публичный ключ клиента (вставьте содержимое файла client1_public.key)
PublicKey = <CLIENT_PUBLIC_KEY>

# Разрешенные IP адреса для этого клиента
AllowedIPs = 10.0.0.2/32
```

**Важно:** Вставляйте сам публичный ключ, а не путь к файлу!

**Быстрый способ добавления клиента:**

```bash
# Добавить клиента автоматически (замените 10.0.0.2 на нужный IP)
echo "" >> /etc/wireguard/wg0.conf
echo "[Peer]" >> /etc/wireguard/wg0.conf
echo "PublicKey = $(cat /etc/wireguard/client1_public.key)" >> /etc/wireguard/wg0.conf
echo "AllowedIPs = 10.0.0.2/32" >> /etc/wireguard/wg0.conf
```

После добавления клиента:

```bash
# Перезагрузить конфигурацию WireGuard
wg-quick down wg0
wg-quick up wg0

# Или применить изменения без перезапуска (вставьте реальный публичный ключ)
wg set wg0 peer $(cat /etc/wireguard/client1_public.key) allowed-ips 10.0.0.2/32
```

## Шаг 11: Создание конфигурации для клиента

Создайте файл конфигурации для клиента (например, `client1.conf`):

```
[Interface]
# Приватный ключ клиента
PrivateKey = <CLIENT_PRIVATE_KEY>

# IP адрес клиента в сети WireGuard
Address = 10.0.0.2/24

# DNS сервер (опционально)
DNS = 8.8.8.8, 8.8.4.4

[Peer]
# Публичный ключ сервера
PublicKey = <SERVER_PUBLIC_KEY>

# IP адрес сервера
Endpoint = 80.233.165.55:51820

# Разрешенные IP адреса (0.0.0.0/0 для всего трафика через VPN)
AllowedIPs = 0.0.0.0/0

# Keepalive (опционально, для прохождения через NAT)
PersistentKeepalive = 25
```

## Управление WireGuard

```bash
# Запустить интерфейс
wg-quick up wg0

# Остановить интерфейс
wg-quick down wg0

# Перезагрузить конфигурацию
wg-quick down wg0 && wg-quick up wg0

# Просмотр статуса
wg show wg0

# Просмотр всех подключенных клиентов
wg show

# Удалить клиента
wg set wg0 peer <CLIENT_PUBLIC_KEY> remove
```

## Безопасность

1. **Защита ключей:**
   ```bash
   chmod 600 /etc/wireguard/*.key
   chmod 600 /etc/wireguard/wg0.conf
   ```

2. **Ограничение доступа к конфигурации:**
   ```bash
   chown root:root /etc/wireguard/wg0.conf
   ```

3. **Регулярное обновление системы:**
   ```bash
   apt update && apt upgrade -y
   ```

4. **Сохранение правил iptables при перезагрузке:**
   ```bash
   # Убедитесь, что правила сохранены
   iptables-save > /etc/iptables/rules.v4
   
   # Включить автозагрузку правил iptables
   systemctl enable netfilter-persistent
   ```

## Устранение неполадок

### Ошибка "resolvconf: command not found"

Если вы получили ошибку:
```
/usr/bin/wg-quick: line 32: resolvconf: command not found
```

**Причина:** В конфигурации указан DNS сервер, но утилита `resolvconf` не установлена.

**Решение 1 (рекомендуется):** Убрать DNS из конфигурации сервера (DNS обычно нужен только клиентам):

```bash
nano /etc/wireguard/wg0.conf
```

Закомментируйте или удалите строку с DNS:
```
# DNS = 8.8.8.8, 8.8.4.4
```

Или удалите строку полностью. Затем запустите снова:
```bash
wg-quick up wg0
```

**Решение 2:** Установить resolvconf (если DNS действительно нужен на сервере):

```bash
apt install resolvconf -y
# или
apt install openresolv -y
```

После установки попробуйте запустить снова:
```bash
wg-quick up wg0
```

**Быстрое исправление (удаление DNS из конфигурации):**
```bash
# Закомментировать строку DNS
sed -i 's/^DNS =/#DNS =/' /etc/wireguard/wg0.conf
```

### Ошибка "Key is not the correct length or format"

Если вы получили ошибку:
```
Key is not the correct length or format: `/etc/wireguard/server_private.key'
```

**Причина:** В конфигурации указан путь к файлу вместо самого ключа.

**Решение:**

1. Просмотрите содержимое файла ключа:
   ```bash
   cat /etc/wireguard/server_private.key
   ```

2. Откройте конфигурацию:
   ```bash
   nano /etc/wireguard/wg0.conf
   ```

3. Найдите строку `PrivateKey = ...` и замените путь к файлу на сам ключ:
   ```
   # Неправильно:
   PrivateKey = /etc/wireguard/server_private.key
   
   # Правильно:
   PrivateKey = SHtbN2D9LhDEf/TKPb3YN761TRke/NB9cuzMw+b7vEQ=
   ```

4. Сохраните файл и попробуйте запустить снова:
   ```bash
   wg-quick up wg0
   ```

**Быстрое исправление:**
```bash
# Автоматически исправить конфигурацию
sed -i "s|PrivateKey = /etc/wireguard/server_private.key|PrivateKey = $(cat /etc/wireguard/server_private.key)|" /etc/wireguard/wg0.conf
```

### Проверка статуса службы
```bash
systemctl status wg-quick@wg0
```

### Просмотр логов
```bash
journalctl -u wg-quick@wg0 -n 50
```

### Проверка файрвола iptables
```bash
# Просмотр всех правил
iptables -L -n -v

# Просмотр правил NAT
iptables -t nat -L -n -v

# Проверка конкретного порта
iptables -L INPUT -n -v | grep 51820
```

### Проверка IP forwarding
```bash
sysctl net.ipv4.ip_forward
```

### Тест подключения с клиента
```bash
# На клиенте
ping 10.0.0.1
```

### Восстановление правил iptables при проблемах
```bash
# Если заблокировали себя, подключитесь через консоль датацентра
# Восстановить правила из сохраненного файла
iptables-restore < /etc/iptables/rules.v4
```

## Дополнительные настройки

### Изменение порта WireGuard

Если нужно использовать другой порт (например, 51821):

1. Измените `ListenPort` в `/etc/wireguard/wg0.conf`
2. Обновите правило файрвола:
   ```bash
   # Удалить старое правило
   iptables -D INPUT -p udp --dport 51820 -j ACCEPT
   
   # Добавить новое правило
   iptables -A INPUT -p udp --dport 51821 -j ACCEPT
   
   # Сохранить правила
   iptables-save > /etc/iptables/rules.v4
   ```
3. Перезапустите WireGuard

### Настройка автоматического обновления

```bash
apt install unattended-upgrades -y
dpkg-reconfigure -plow unattended-upgrades
```

## Полезные команды

```bash
# Просмотр статистики передачи данных
wg show wg0 transfer

# Просмотр последнего рукопожатия
wg show wg0 latest-handshakes

# Мониторинг в реальном времени
watch -n 1 'wg show'

# Просмотр правил iptables с номерами строк
iptables -L INPUT --line-numbers -n -v

# Удаление правила iptables по номеру строки
# iptables -D INPUT <номер_строки>
```

## Примечания

- IP адрес сервера: **80.233.165.55**
- Порт по умолчанию: **51820/UDP**
- Подсеть WireGuard: **10.0.0.0/24** (можно изменить при необходимости)
- Убедитесь, что порт 51820/UDP открыт в файрволе датацентра, если используется внешний файрвол

