#!/bin/bash

###############################################################################
# WireGuard Peer Management Script with TUI
# Скрипт для создания пиров WireGuard через текстовый интерфейс
###############################################################################

# Настройка кодировки и терминала для корректного отображения
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TERM=xterm-256color

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Константы конфигурации
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
PEERS_DIR="${WG_DIR}/peers_conf"
SERVER_IP="80.233.165.55"  # Внешний IP сервера (можно переопределить из конфига)
WG_INTERFACE="wg0"

# Эти значения будут определены автоматически из конфигурации
SERVER_PORT=""
WG_SUBNET=""
WG_SERVER_IP=""
WG_BASE_IP=""
WG_NETMASK=""

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root${NC}"
        exit 1
    fi
}

# Проверка и установка TUI библиотек
check_and_install_tui() {
    echo -e "${YELLOW}Проверка наличия TUI библиотек...${NC}"
    
    # Проверяем наличие dialog
    if command -v dialog &> /dev/null; then
        echo -e "${GREEN}✓ dialog найден${NC}"
        TUI_CMD="dialog"
        # Используем ASCII символы для рамок
        export DIALOGOPTS="--ascii-lines --no-shadow --colors"
        return 0
    fi
    
    # Проверяем наличие whiptail
    if command -v whiptail &> /dev/null; then
        echo -e "${GREEN}✓ whiptail найден${NC}"
        TUI_CMD="whiptail"
        return 0
    fi
    
    # Если ничего не найдено, предлагаем установить
    echo -e "${YELLOW}TUI библиотеки не найдены. Попытка установки...${NC}"
    
    # Определяем менеджер пакетов
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        if apt-get install -y dialog 2>/dev/null; then
            echo -e "${GREEN}✓ dialog успешно установлен${NC}"
            TUI_CMD="dialog"
            return 0
        elif apt-get install -y whiptail 2>/dev/null; then
            echo -e "${GREEN}✓ whiptail успешно установлен${NC}"
            TUI_CMD="whiptail"
            return 0
        else
            echo -e "${RED}Ошибка: Не удалось установить dialog или whiptail${NC}"
            echo -e "${YELLOW}Попробуйте установить вручную:${NC}"
            echo "  apt-get install dialog"
            echo "  или"
            echo "  apt-get install whiptail"
            exit 1
        fi
    elif command -v yum &> /dev/null; then
        if yum install -y dialog 2>/dev/null; then
            echo -e "${GREEN}✓ dialog успешно установлен${NC}"
            TUI_CMD="dialog"
            return 0
        else
            echo -e "${RED}Ошибка: Не удалось установить dialog${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Ошибка: Не найден поддерживаемый менеджер пакетов${NC}"
        echo -e "${YELLOW}Установите dialog или whiptail вручную${NC}"
        exit 1
    fi
}

# Функция для показа сообщений через TUI
show_msg() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-60}"
    
    if [ "$TUI_CMD" = "dialog" ]; then
        dialog --clear --ascii-lines --no-shadow --backtitle "WireGuard Peer Manager" --title "$title" --msgbox "$message" "$height" "$width" 2>&1 >/dev/tty
        # Очищаем экран после диалога
        clear
    else
        whiptail --title "$title" --msgbox "$message" "$height" "$width" 2>&1 >/dev/tty
        clear
    fi
}

# Функция для ввода текста через TUI
input_text() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local height="${4:-10}"
    local width="${5:-60}"
    
    if [ "$TUI_CMD" = "dialog" ]; then
        dialog --clear --ascii-lines --no-shadow --backtitle "WireGuard Peer Manager" --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 2>&1 >/dev/tty
    else
        whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$default" 2>&1 >/dev/tty
    fi
}

# Функция для выбора опций через TUI
select_option() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    local height="${#options[@]}"
    local width=60
    local result=""
    
    if [ "$TUI_CMD" = "dialog" ]; then
        local menu_items=()
        local i=0
        for opt in "${options[@]}"; do
            menu_items+=("$i" "$opt")
            ((i++))
        done
        result=$(dialog --clear --ascii-lines --no-shadow --backtitle "WireGuard Peer Manager" --title "$title" --menu "$prompt" "$height" "$width" "$height" "${menu_items[@]}" 2>&1 >/dev/tty)
        echo "$result"
    else
        local menu_items=()
        local i=0
        for opt in "${options[@]}"; do
            menu_items+=("$opt" "")
            ((i++))
        done
        result=$(whiptail --title "$title" --menu "$prompt" "$height" "$width" "$height" "${menu_items[@]}" 2>&1 >/dev/tty)
        # Преобразуем текст обратно в индекс
        local idx=0
        for opt in "${options[@]}"; do
            if [ "$result" = "$opt" ]; then
                echo "$idx"
                return 0
            fi
            ((idx++))
        done
        echo ""
    fi
}

# Функция для yes/no диалога
yesno_dialog() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-60}"
    
    if [ "$TUI_CMD" = "dialog" ]; then
        dialog --clear --ascii-lines --no-shadow --backtitle "WireGuard Peer Manager" --title "$title" --yesno "$message" "$height" "$width" 2>&1 >/dev/tty
    else
        whiptail --title "$title" --yesno "$message" "$height" "$width" 2>&1 >/dev/tty
    fi
}

# Чтение параметров из конфигурации WireGuard
read_wg_config() {
    if [ ! -f "$WG_CONF" ]; then
        show_msg "Ошибка" "Конфигурация WireGuard не найдена!\n\nФайл $WG_CONF не существует.\nСначала настройте сервер WireGuard." 12 70
        exit 1
    fi
    
    # Читаем IP адрес сервера и подсеть
    while IFS= read -r line; do
        # Пропускаем комментарии и пустые строки
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Извлекаем Address (например: Address = 10.77.0.1/24)
        if [[ $line =~ ^[[:space:]]*Address[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)/([0-9]+) ]]; then
            WG_SERVER_IP="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
            WG_BASE_IP="${BASH_REMATCH[1]}"  # Базовый IP без последнего октета (например, 10.77.0)
            WG_NETMASK="${BASH_REMATCH[3]}"
            
            # Формируем подсеть (например, 10.77.0.0/24)
            local ip_parts=(${BASH_REMATCH[1]//./ })
            WG_SUBNET="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.0/${BASH_REMATCH[3]}"
        fi
        
        # Извлекаем ListenPort (например: ListenPort = 47770)
        if [[ $line =~ ^[[:space:]]*ListenPort[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
            SERVER_PORT="${BASH_REMATCH[1]}"
        fi
    done < "$WG_CONF"
    
    # Проверяем, что все параметры определены
    if [ -z "$WG_SERVER_IP" ] || [ -z "$WG_SUBNET" ]; then
        show_msg "Ошибка" "Не удалось определить параметры из конфигурации!\n\nПроверьте файл $WG_CONF.\nУбедитесь, что указан Address в формате IP/маска." 12 70
        exit 1
    fi
    
    # Если порт не найден, используем значение по умолчанию
    if [ -z "$SERVER_PORT" ]; then
        SERVER_PORT="51820"
        echo -e "${YELLOW}Предупреждение: Порт не найден в конфигурации, используется значение по умолчанию: $SERVER_PORT${NC}"
    fi
    
}

# Проверка наличия WireGuard
check_wireguard() {
    if ! command -v wg &> /dev/null; then
        show_msg "Ошибка" "WireGuard не установлен!\n\nУстановите WireGuard:\napt-get install wireguard wireguard-tools" 12 70
        exit 1
    fi
    
    if [ ! -f "$WG_CONF" ]; then
        show_msg "Ошибка" "Конфигурация WireGuard не найдена!\n\nФайл $WG_CONF не существует.\nСначала настройте сервер WireGuard." 12 70
        exit 1
    fi
}

# Получение публичного ключа сервера
get_server_public_key() {
    if [ -f "${WG_DIR}/server_public.key" ]; then
        SERVER_PUBLIC_KEY=$(cat "${WG_DIR}/server_public.key")
    else
        # Пытаемся извлечь из конфигурации
        SERVER_PUBLIC_KEY=$(wg show "$WG_INTERFACE" public-key 2>/dev/null)
        if [ -z "$SERVER_PUBLIC_KEY" ]; then
            show_msg "Ошибка" "Не удалось получить публичный ключ сервера!\n\nПроверьте конфигурацию WireGuard." 10 70
            exit 1
        fi
    fi
}

# Определение следующего доступного IP адреса
get_next_ip() {
    local start=2
    local end=254
    local used_ips=()
    
    # Используем базовый IP из конфигурации (например, 10.77.0)
    local base_ip="$WG_BASE_IP"
    
    if [ -z "$base_ip" ]; then
        echo ""
        return 1
    fi
    
    # Получаем список используемых IP из конфигурации сервера
    if [ -f "$WG_CONF" ]; then
        while IFS= read -r line; do
            # Пропускаем комментарии
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            
            # Ищем AllowedIPs (например: AllowedIPs = 10.77.0.2/32)
            if [[ $line =~ AllowedIPs[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+) ]]; then
                local ip="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
                # Проверяем, что IP принадлежит нашей подсети
                if [[ "$ip" =~ ^${base_ip//./\\.}\.([0-9]+)$ ]]; then
                    used_ips+=("${BASH_REMATCH[1]}")
                fi
            fi
        done < "$WG_CONF"
    fi
    
    # Проверяем существующие конфигурации пиров
    if [ -d "$PEERS_DIR" ]; then
        for peer_file in "$PEERS_DIR"/*.conf; do
            if [ -f "$peer_file" ]; then
                while IFS= read -r line; do
                    # Пропускаем комментарии
                    [[ "$line" =~ ^[[:space:]]*# ]] && continue
                    
                    # Ищем Address (например: Address = 10.77.0.2/24)
                    if [[ $line =~ Address[[:space:]]*=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+) ]]; then
                        local ip="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
                        # Проверяем, что IP принадлежит нашей подсети
                        if [[ "$ip" =~ ^${base_ip//./\\.}\.([0-9]+)$ ]]; then
                            used_ips+=("${BASH_REMATCH[1]}")
                        fi
                    fi
                done < "$peer_file"
            fi
        done
    fi
    
    # Добавляем IP сервера в список использованных
    if [[ "$WG_SERVER_IP" =~ ^${base_ip//./\\.}\.([0-9]+)$ ]]; then
        used_ips+=("${BASH_REMATCH[1]}")
    fi
    
    # Находим первый свободный IP
    for i in $(seq $start $end); do
        local found=0
        for used in "${used_ips[@]}"; do
            if [ "$i" -eq "$used" ]; then
                found=1
                break
            fi
        done
        if [ $found -eq 0 ]; then
            echo "${base_ip}.${i}"
            return 0
        fi
    done
    
    echo ""
}

# Создание директории для конфигураций пиров
create_peers_dir() {
    if [ ! -d "$PEERS_DIR" ]; then
        mkdir -p "$PEERS_DIR"
        chmod 700 "$PEERS_DIR"
    fi
}

# Генерация ключей для пира
generate_peer_keys() {
    local peer_name="$1"
    local private_key_file="${WG_DIR}/${peer_name}_private.key"
    local public_key_file="${WG_DIR}/${peer_name}_public.key"
    
    # Генерируем приватный ключ
    wg genkey > "$private_key_file"
    chmod 600 "$private_key_file"
    
    # Генерируем публичный ключ из приватного
    wg pubkey < "$private_key_file" > "$public_key_file"
    chmod 644 "$public_key_file"
    
    PEER_PRIVATE_KEY=$(cat "$private_key_file")
    PEER_PUBLIC_KEY=$(cat "$public_key_file")
}

# Добавление пира в конфигурацию сервера
add_peer_to_server() {
    local peer_public_key="$1"
    local peer_ip="$2"
    
    # Проверяем, не добавлен ли уже этот пир
    if grep -q "PublicKey = $peer_public_key" "$WG_CONF" 2>/dev/null; then
        return 1
    fi
    
    # Добавляем пира в конфигурацию
    {
        echo ""
        echo "[Peer]"
        echo "# Публичный ключ пира: $PEER_NAME"
        echo "PublicKey = $peer_public_key"
        echo "AllowedIPs = ${peer_ip}/32"
    } >> "$WG_CONF"
    
    return 0
}

# Применение изменений к WireGuard
apply_wg_changes() {
    # Пытаемся применить изменения без перезапуска
    if wg show "$WG_INTERFACE" &>/dev/null; then
        wg set "$WG_INTERFACE" peer "$PEER_PUBLIC_KEY" allowed-ips "${PEER_IP}/32" 2>/dev/null
        if [ $? -eq 0 ]; then
            return 0
        fi
    fi
    
    # Если не получилось, перезапускаем интерфейс
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        wg-quick down "$WG_INTERFACE" 2>/dev/null
        sleep 1
        wg-quick up "$WG_INTERFACE" 2>/dev/null
    fi
    
    return 0
}

# Создание конфигурационного файла для пира
create_peer_config() {
    local peer_name="$1"
    local peer_ip="$2"
    local peer_private_key="$3"
    local dns_servers="$4"
    local allowed_ips="$5"
    
    local config_file="${PEERS_DIR}/${peer_name}.conf"
    
    # Определяем маску подсети для клиента
    local client_netmask="${WG_NETMASK:-24}"
    
    cat > "$config_file" <<EOF
[Interface]
# Приватный ключ пира
PrivateKey = $peer_private_key

# IP адрес пира в сети WireGuard
Address = ${peer_ip}/${client_netmask}

# DNS серверы
DNS = $dns_servers

[Peer]
# Публичный ключ сервера
PublicKey = $SERVER_PUBLIC_KEY

# IP адрес и порт сервера
Endpoint = ${SERVER_IP}:${SERVER_PORT}

# Разрешенные IP адреса (0.0.0.0/0 для всего трафика через VPN)
AllowedIPs = $allowed_ips

# Keepalive для прохождения через NAT
PersistentKeepalive = 25
EOF
    
    chmod 600 "$config_file"
    echo "$config_file"
}

# Вывод конфигурации в STDOUT
print_peer_config() {
    local config_file="$1"
    
    echo ""
    echo "=========================================="
    echo "Конфигурация пира: $PEER_NAME"
    echo "=========================================="
    echo ""
    cat "$config_file"
    echo ""
    echo "=========================================="
    echo ""
}

# Основная функция создания пира
create_peer() {
    # Запрашиваем имя пира
    PEER_NAME=$(input_text "Создание пира WireGuard" "Введите имя пира (латиница, без пробелов):" "" 10 60)
    
    if [ -z "$PEER_NAME" ]; then
        show_msg "Отмена" "Создание пира отменено пользователем." 8 50
        exit 0
    fi
    
    # Проверяем, что имя содержит только допустимые символы
    if [[ ! "$PEER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        show_msg "Ошибка" "Имя пира может содержать только буквы, цифры, дефисы и подчеркивания!" 10 60
        exit 1
    fi
    
    # Проверяем, не существует ли уже пир с таким именем
    if [ -f "${PEERS_DIR}/${PEER_NAME}.conf" ]; then
        if ! yesno_dialog "Подтверждение" "Пир с именем '$PEER_NAME' уже существует.\nПерезаписать?" 10 60; then
            exit 0
        fi
    fi
    
    # Определяем IP адрес
    PEER_IP=$(get_next_ip)
    if [ -z "$PEER_IP" ]; then
        show_msg "Ошибка" "Не удалось найти свободный IP адрес в подсети $WG_SUBNET" 10 60
        exit 1
    fi
    
    # Запрашиваем DNS серверы
    DNS_CHOICE=$(select_option "Настройка DNS" "Выберите DNS серверы:" \
        "8.8.8.8, 8.8.4.4 (Google)" \
        "1.1.1.1, 1.0.0.1 (Cloudflare)" \
        "208.67.222.222, 208.67.220.220 (OpenDNS)" \
        "Другое (ввести вручную)")
    
    if [ -z "$DNS_CHOICE" ]; then
        show_msg "Отмена" "Создание пира отменено пользователем." 8 50
        exit 0
    fi
    
    case "$DNS_CHOICE" in
        0)
            DNS_SERVERS="8.8.8.8, 8.8.4.4"
            ;;
        1)
            DNS_SERVERS="1.1.1.1, 1.0.0.1"
            ;;
        2)
            DNS_SERVERS="208.67.222.222, 208.67.220.220"
            ;;
        3)
            DNS_SERVERS=$(input_text "DNS серверы" "Введите DNS серверы (через запятую):" "8.8.8.8, 8.8.4.4" 10 60)
            if [ -z "$DNS_SERVERS" ]; then
                show_msg "Отмена" "Создание пира отменено пользователем." 8 50
                exit 0
            fi
            ;;
        *)
            DNS_SERVERS="8.8.8.8, 8.8.4.4"
            ;;
    esac
    
    # Запрашиваем AllowedIPs
    ALLOWED_IPS_CHOICE=$(select_option "Настройка маршрутизации" "Выберите режим маршрутизации:" \
        "0.0.0.0/0 (весь трафик через VPN)" \
        "${WG_SUBNET} (только сеть WireGuard)" \
        "Другое (ввести вручную)")
    
    if [ -z "$ALLOWED_IPS_CHOICE" ]; then
        show_msg "Отмена" "Создание пира отменено пользователем." 8 50
        exit 0
    fi
    
    case "$ALLOWED_IPS_CHOICE" in
        0)
            ALLOWED_IPS="0.0.0.0/0"
            ;;
        1)
            ALLOWED_IPS="$WG_SUBNET"
            ;;
        2)
            ALLOWED_IPS=$(input_text "AllowedIPs" "Введите AllowedIPs:" "0.0.0.0/0" 10 60)
            if [ -z "$ALLOWED_IPS" ]; then
                show_msg "Отмена" "Создание пира отменено пользователем." 8 50
                exit 0
            fi
            ;;
        *)
            ALLOWED_IPS="0.0.0.0/0"
            ;;
    esac
    
    # Показываем сводку
    SUMMARY="Сводка настроек пира:\n\n"
    SUMMARY+="Имя пира: $PEER_NAME\n"
    SUMMARY+="IP адрес: $PEER_IP\n"
    SUMMARY+="DNS серверы: $DNS_SERVERS\n"
    SUMMARY+="AllowedIPs: $ALLOWED_IPS\n\n"
    SUMMARY+="Продолжить создание?"
    
    if ! yesno_dialog "Подтверждение" "$SUMMARY" 15 60; then
        exit 0
    fi
    
    # Генерируем ключи
    generate_peer_keys "$PEER_NAME"
    
    # Добавляем пира в конфигурацию сервера
    if ! add_peer_to_server "$PEER_PUBLIC_KEY" "$PEER_IP"; then
        show_msg "Ошибка" "Пир с таким публичным ключом уже существует в конфигурации сервера!" 10 60
        exit 1
    fi
    
    # Создаем конфигурационный файл для пира
    CONFIG_FILE=$(create_peer_config "$PEER_NAME" "$PEER_IP" "$PEER_PRIVATE_KEY" "$DNS_SERVERS" "$ALLOWED_IPS")
    
    # Применяем изменения к WireGuard
    apply_wg_changes
    
    # Выводим конфигурацию в STDOUT
    print_peer_config "$CONFIG_FILE"
    
    # Показываем успешное сообщение
    SUCCESS_MSG="Пир успешно создан!\n\n"
    SUCCESS_MSG+="Имя: $PEER_NAME\n"
    SUCCESS_MSG+="IP: $PEER_IP\n"
    SUCCESS_MSG+="Конфигурация сохранена в:\n$CONFIG_FILE\n\n"
    SUCCESS_MSG+="Конфигурация также выведена в STDOUT."
    
    show_msg "Успех" "$SUCCESS_MSG" 12 70
    
    # Очищаем экран после завершения TUI
    clear
}

# Функция очистки экрана при выходе
cleanup_on_exit() {
    # Выходим из альтернативного режима экрана (если dialog его включил)
    tput rmcup 2>/dev/null
    # Очищаем экран
    clear
    # Сбрасываем терминал в нормальное состояние
    tput reset 2>/dev/null || reset 2>/dev/null || clear
    # Возвращаем курсор в нормальное состояние
    tput cnorm 2>/dev/null
    # Показываем курсор
    echo -ne "\033[?25h"
}

# Главная функция
main() {
    # Устанавливаем обработчик для очистки экрана при выходе
    trap cleanup_on_exit EXIT
    
    check_root
    check_and_install_tui
    check_wireguard
    read_wg_config
    get_server_public_key
    create_peers_dir
    create_peer
    
    # Очищаем экран перед выходом
    clear
    tput reset 2>/dev/null || reset 2>/dev/null || clear
}

# Запуск скрипта
main "$@"

