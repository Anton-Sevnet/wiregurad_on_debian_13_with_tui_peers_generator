# Проверка и установка TUI библиотек для скрипта управления WireGuard пирами

## Что такое TUI?

TUI (Text User Interface) - это текстовый пользовательский интерфейс, который позволяет создавать интерактивные меню и диалоги в терминале.

## Используемые библиотеки

Скрипт `wg-add-peer.sh` использует одну из следующих библиотек:
- **dialog** (предпочтительно) - более функциональная и удобная
- **whiptail** (альтернатива) - более легковесная, но менее функциональная

## Проверка наличия TUI библиотек

### Проверка dialog

```bash
command -v dialog
```

Если команда вернула путь (например, `/usr/bin/dialog`), то `dialog` установлен.

### Проверка whiptail

```bash
command -v whiptail
```

Если команда вернула путь (например, `/usr/bin/whiptail`), то `whiptail` установлен.

### Быстрая проверка обеих библиотек

```bash
if command -v dialog &> /dev/null; then
    echo "dialog найден"
elif command -v whiptail &> /dev/null; then
    echo "whiptail найден"
else
    echo "TUI библиотеки не найдены"
fi
```

## Установка TUI библиотек

### На Debian/Ubuntu

#### Установка dialog (рекомендуется)

```bash
apt-get update
apt-get install -y dialog
```

#### Установка whiptail (альтернатива)

```bash
apt-get update
apt-get install -y whiptail
```

### На CentOS/RHEL/Fedora

#### Установка dialog

```bash
yum install -y dialog
```

или для новых версий:

```bash
dnf install -y dialog
```

#### Установка whiptail

```bash
yum install -y newt
```

или для новых версий:

```bash
dnf install -y newt
```

### На Alpine Linux

```bash
apk add dialog
```

или

```bash
apk add whiptail
```

## Автоматическая установка через скрипт

Скрипт `wg-add-peer.sh` автоматически проверяет наличие TUI библиотек и предлагает установить их при первом запуске, если они отсутствуют.

**Важно:** Для автоматической установки скрипт должен запускаться от root и иметь доступ к интернету.

## Проверка работы TUI

После установки можно проверить работу библиотеки:

### Тест dialog

```bash
dialog --msgbox "Тест dialog" 10 30
```

### Тест whiptail

```bash
whiptail --msgbox "Тест whiptail" 10 30
```

## Различия между dialog и whiptail

| Функция | dialog | whiptail |
|---------|--------|----------|
| Функциональность | Более богатая | Базовая |
| Размер | Больше | Меньше |
| Поддержка цветов | Да | Ограниченная |
| Поддержка тем | Да | Нет |
| Совместимость | Широкая | Ограниченная |

**Рекомендация:** Используйте `dialog` для лучшего пользовательского опыта.

## Устранение проблем

### Ошибка: "dialog: command not found"

**Решение:**
```bash
apt-get update && apt-get install -y dialog
```

### Ошибка: "whiptail: command not found"

**Решение:**
```bash
apt-get update && apt-get install -y whiptail
```

### Ошибка при установке: "Unable to locate package"

**Решение:**
1. Обновите список пакетов:
   ```bash
   apt-get update
   ```

2. Проверьте доступность репозиториев:
   ```bash
   apt-cache search dialog
   ```

### TUI не отображается корректно

**Возможные причины:**
1. Неправильный размер терминала
2. Неподдерживаемый терминал

**Решение:**
1. Увеличьте размер окна терминала
2. Используйте стандартный терминал (xterm, gnome-terminal, etc.)
3. Проверьте переменную окружения `TERM`:
   ```bash
   echo $TERM
   export TERM=xterm-256color
   ```

## Дополнительная информация

- Документация dialog: `man dialog`
- Документация whiptail: `man whiptail`
- Официальный сайт dialog: https://invisible-island.net/dialog/

