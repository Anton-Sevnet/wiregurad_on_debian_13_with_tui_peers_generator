# PersistentKeepalive в WireGuard - объяснение

## Вопрос: Почему на сервере нет PersistentKeepalive?

### Краткий ответ

**PersistentKeepalive указывается только на КЛИЕНТЕ, а не на сервере.** Это правильно и соответствует архитектуре WireGuard.

### Подробное объяснение

#### Что такое PersistentKeepalive?

`PersistentKeepalive` - это параметр, который указывает клиенту отправлять периодические "keepalive" пакеты серверу для поддержания соединения через NAT (Network Address Translation).

#### Почему это нужно?

Когда клиент находится за NAT (например, домашний роутер), NAT таблица может закрыть соединение, если нет активности в течение определенного времени. Keepalive пакеты предотвращают закрытие соединения.

#### Где указывается PersistentKeepalive?

- ✅ **На КЛИЕНТЕ** - в секции `[Peer]` конфигурации клиента
- ❌ **НЕ на сервере** - сервер не отправляет keepalive пакеты клиентам

#### Пример правильной конфигурации

**На сервере (`/etc/wireguard/wg0.conf`):**
```ini
[Peer]
# Публичный ключ пира: anton_sevnet
PublicKey = uldAjVywUbjTxIPvxn133x8OwgGdTyBLw+9eHS4IfGk=
AllowedIPs = 10.77.0.2/32
# PersistentKeepalive НЕ указывается здесь!
```

**На клиенте (`peer.conf`):**
```ini
[Peer]
PublicKey = lVfCZt2tVxAVrQVUnqFXypkrTkOEnwRpbTvP7r/opQc=
AllowedIPs = 0.0.0.0/0
Endpoint = 80.233.165.55:47770
PersistentKeepalive = 25  # ✅ Указывается здесь!
```

#### Что означает значение 25?

`PersistentKeepalive = 25` означает, что клиент будет отправлять keepalive пакет каждые 25 секунд, если нет другой активности.

### Вывод

Если на сервере нет `PersistentKeepalive` - это **нормально и правильно**. Этот параметр должен быть только в конфигурации клиента.

## Дополнительная информация

- WireGuard сервер обычно имеет статический IP адрес и не находится за NAT, поэтому ему не нужны keepalive пакеты
- Если клиент находится за NAT, он должен иметь `PersistentKeepalive` в своей конфигурации
- Скрипт `wg-add-peer.sh` автоматически добавляет `PersistentKeepalive = 25` в конфигурацию клиента

