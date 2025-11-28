#!/bin/bash

###############################################################################
# Скрипт для обновления AllowedIPs существующего пира WireGuard
# Позволяет добавить дополнительные сети (например, домашнюю сеть клиента)
###############################################################################

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Константы
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
WG_INTERFACE="wg0"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root${NC}"
    exit 1
fi

# Проверка существования конфигурации
if [ ! -f "$WG_CONF" ]; then
    echo -e "${RED}Ошибка: Конфигурация WireGuard не найдена: $WG_CONF${NC}"
    exit 1
fi

# Функция для отображения списка пиров
list_peers() {
    echo -e "${BLUE}Список пиров в конфигурации:${NC}"
    echo ""
    
    local peer_count=0
    local peer_name=""
    local peer_public_key=""
    local peer_allowed_ips=""
    
    while IFS= read -r line; do
        # Ищем начало секции [Peer]
        if [[ $line =~ ^\[Peer\] ]]; then
            if [ $peer_count -gt 0 ]; then
                echo -e "${GREEN}  $peer_count. $peer_name${NC}"
                echo -e "     PublicKey: ${peer_public_key:0:20}..."
                echo -e "     AllowedIPs: $peer_allowed_ips"
                echo ""
            fi
            peer_count=$((peer_count + 1))
            peer_name=""
            peer_public_key=""
            peer_allowed_ips=""
        # Ищем комментарий с именем пира
        elif [[ $line =~ ^#.*Публичный\ ключ\ пира:\ (.+)$ ]]; then
            peer_name="${BASH_REMATCH[1]}"
        # Ищем PublicKey
        elif [[ $line =~ ^PublicKey[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            peer_public_key="${BASH_REMATCH[1]}"
        # Ищем AllowedIPs
        elif [[ $line =~ ^AllowedIPs[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            peer_allowed_ips="${BASH_REMATCH[1]}"
        fi
    done < "$WG_CONF"
    
    # Выводим последнего пира
    if [ $peer_count -gt 0 ] && [ -n "$peer_name" ]; then
        echo -e "${GREEN}  $peer_count. $peer_name${NC}"
        echo -e "     PublicKey: ${peer_public_key:0:20}..."
        echo -e "     AllowedIPs: $peer_allowed_ips"
        echo ""
    fi
    
    echo $peer_count
}

# Функция для получения текущих AllowedIPs пира
get_peer_allowedips() {
    local peer_public_key="$1"
    local in_peer_section=false
    local allowed_ips=""
    
    while IFS= read -r line; do
        if [[ $line =~ ^\[Peer\] ]]; then
            in_peer_section=false
        fi
        
        if [[ $line =~ ^PublicKey[[:space:]]*=[[:space:]]*$peer_public_key ]]; then
            in_peer_section=true
        fi
        
        if [ "$in_peer_section" = true ] && [[ $line =~ ^AllowedIPs[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            allowed_ips="${BASH_REMATCH[1]}"
            break
        fi
    done < "$WG_CONF"
    
    echo "$allowed_ips"
}

# Функция для обновления AllowedIPs пира
update_peer_allowedips() {
    local peer_public_key="$1"
    local new_allowed_ips="$2"
    
    # Создаем временный файл
    local temp_file=$(mktemp)
    
    local in_peer_section=false
    local peer_section_start=0
    local peer_section_end=0
    local line_num=0
    
    # Читаем файл и находим секцию пира
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        if [[ $line =~ ^\[Peer\] ]]; then
            if [ "$in_peer_section" = true ]; then
                # Завершаем предыдущую секцию
                peer_section_end=$((line_num - 1))
                break
            fi
            peer_section_start=$line_num
            in_peer_section=false
        fi
        
        if [[ $line =~ ^PublicKey[[:space:]]*=[[:space:]]*$peer_public_key ]]; then
            in_peer_section=true
        fi
    done < "$WG_CONF"
    
    if [ "$in_peer_section" = true ]; then
        peer_section_end=$line_num
    fi
    
    if [ $peer_section_start -eq 0 ]; then
        echo -e "${RED}Ошибка: Пир с указанным PublicKey не найден${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    # Копируем файл до секции пира
    head -n $((peer_section_start - 1)) "$WG_CONF" > "$temp_file"
    
    # Находим и обновляем AllowedIPs в секции пира
    local peer_name=""
    local found_allowedips=false
    
    while IFS= read -r line; do
        if [[ $line =~ ^#.*Публичный\ ключ\ пира:\ (.+)$ ]]; then
            peer_name="${BASH_REMATCH[1]}"
            echo "$line" >> "$temp_file"
        elif [[ $line =~ ^PublicKey[[:space:]]*= ]]; then
            echo "$line" >> "$temp_file"
        elif [[ $line =~ ^AllowedIPs[[:space:]]*= ]]; then
            echo "AllowedIPs = $new_allowed_ips" >> "$temp_file"
            found_allowedips=true
        else
            echo "$line" >> "$temp_file"
        fi
    done < <(sed -n "${peer_section_start},${peer_section_end}p" "$WG_CONF")
    
    # Если AllowedIPs не было найдено, добавляем его
    if [ "$found_allowedips" = false ]; then
        echo "AllowedIPs = $new_allowed_ips" >> "$temp_file"
    fi
    
    # Копируем остаток файла
    if [ $peer_section_end -lt $line_num ]; then
        tail -n +$((peer_section_end + 1)) "$WG_CONF" >> "$temp_file"
    fi
    
    # Заменяем оригинальный файл
    mv "$temp_file" "$WG_CONF"
    
    echo "$peer_name"
    return 0
}

# Основная функция
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Обновление AllowedIPs для пира WireGuard${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Показываем список пиров
    peer_count=$(list_peers)
    
    if [ "$peer_count" -eq 0 ]; then
        echo -e "${RED}Ошибка: В конфигурации не найдено пиров${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}Введите PublicKey пира для обновления:${NC}"
    read -r PEER_PUBLIC_KEY
    
    if [ -z "$PEER_PUBLIC_KEY" ]; then
        echo -e "${RED}Ошибка: PublicKey не может быть пустым${NC}"
        exit 1
    fi
    
    # Проверяем, существует ли пир
    if ! grep -q "PublicKey = $PEER_PUBLIC_KEY" "$WG_CONF"; then
        echo -e "${RED}Ошибка: Пир с указанным PublicKey не найден${NC}"
        exit 1
    fi
    
    # Получаем текущие AllowedIPs
    current_allowedips=$(get_peer_allowedips "$PEER_PUBLIC_KEY")
    echo -e "${BLUE}Текущие AllowedIPs: $current_allowedips${NC}"
    echo ""
    
    # Запрашиваем новые AllowedIPs
    echo -e "${YELLOW}Введите новые AllowedIPs (можно указать несколько через запятую):${NC}"
    echo -e "${BLUE}Примеры:${NC}"
    echo -e "  ${GREEN}10.77.0.2/32, 0.0.0.0/0, 192.168.77.0/24${NC}  (IP пира + весь трафик + домашняя сеть)"
    echo -e "  ${GREEN}10.77.0.2/32, 192.168.77.0/24${NC}  (IP пира + домашняя сеть)"
    echo ""
    read -r NEW_ALLOWED_IPS
    
    if [ -z "$NEW_ALLOWED_IPS" ]; then
        echo -e "${RED}Ошибка: AllowedIPs не может быть пустым${NC}"
        exit 1
    fi
    
    # Обновляем конфигурацию
    echo ""
    echo -e "${YELLOW}Обновление конфигурации...${NC}"
    
    peer_name=$(update_peer_allowedips "$PEER_PUBLIC_KEY" "$NEW_ALLOWED_IPS")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Конфигурация обновлена для пира: $peer_name${NC}"
        echo ""
        
        # Применяем изменения к WireGuard
        echo -e "${YELLOW}Применение изменений к WireGuard...${NC}"
        
        # Пытаемся обновить без перезапуска
        if wg show "$WG_INTERFACE" &>/dev/null; then
            # Удаляем старые allowed-ips и добавляем новые
            wg set "$WG_INTERFACE" peer "$PEER_PUBLIC_KEY" allowed-ips "$NEW_ALLOWED_IPS" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Изменения применены без перезапуска${NC}"
            else
                echo -e "${YELLOW}⚠ Не удалось применить без перезапуска, перезапускаем интерфейс...${NC}"
                systemctl restart "wg-quick@${WG_INTERFACE}" 2>/dev/null || {
                    wg-quick down "$WG_INTERFACE" 2>/dev/null
                    sleep 1
                    wg-quick up "$WG_INTERFACE" 2>/dev/null
                }
                echo -e "${GREEN}✓ Интерфейс перезапущен${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Интерфейс не активен, изменения будут применены при следующем запуске${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Готово!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}Обновленные AllowedIPs для пира '$peer_name':${NC}"
        echo -e "${GREEN}$NEW_ALLOWED_IPS${NC}"
        echo ""
        echo -e "${YELLOW}Примечание:${NC}"
        echo -e "Если вы добавили домашнюю сеть клиента (например, 192.168.77.0/24),"
        echo -e "убедитесь, что на сервере настроена маршрутизация для этой сети."
        echo ""
    else
        echo -e "${RED}✗ Ошибка при обновлении конфигурации${NC}"
        exit 1
    fi
}

# Запуск скрипта
main "$@"

