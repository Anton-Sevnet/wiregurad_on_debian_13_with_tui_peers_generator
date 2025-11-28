#!/bin/bash

###############################################################################
# Скрипт диагностики и исправления проблемы с доступом в интернет через WireGuard
# Проверяет IP forwarding, правила iptables и исправляет проблемы
###############################################################################

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Константы
WG_INTERFACE="wg0"
WG_CONF="/etc/wireguard/wg0.conf"
SYSCTL_CONF="/etc/sysctl.conf"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Диагностика WireGuard Internet Access${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Функция проверки IP forwarding
check_ip_forwarding() {
    echo -e "${YELLOW}[1/4] Проверка IP forwarding...${NC}"
    
    local current_value=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    
    if [ "$current_value" = "1" ]; then
        echo -e "${GREEN}✓ IP forwarding включен (текущее значение: $current_value)${NC}"
        IP_FORWARDING_OK=true
    else
        echo -e "${RED}✗ IP forwarding выключен (текущее значение: $current_value)${NC}"
        IP_FORWARDING_OK=false
    fi
    
    # Проверяем постоянную настройку
    if grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF" 2>/dev/null; then
        echo -e "${GREEN}✓ IP forwarding настроен для постоянной работы${NC}"
    else
        echo -e "${YELLOW}⚠ IP forwarding не настроен для постоянной работы${NC}"
        IP_FORWARDING_PERSISTENT=false
    fi
    
    echo ""
}

# Функция проверки правил iptables
check_iptables() {
    echo -e "${YELLOW}[2/4] Проверка правил iptables...${NC}"
    
    # Проверяем FORWARD правила для wg0
    local forward_in=$(iptables -L FORWARD -n -v 2>/dev/null | grep -c "wg0.*ACCEPT" || echo "0")
    local forward_out=$(iptables -L FORWARD -n -v 2>/dev/null | grep -c "wg0.*ACCEPT" || echo "0")
    
    if [ "$forward_in" -ge 1 ] && [ "$forward_out" -ge 1 ]; then
        echo -e "${GREEN}✓ Правила FORWARD для wg0 настроены${NC}"
        IPTABLES_FORWARD_OK=true
    else
        echo -e "${RED}✗ Правила FORWARD для wg0 отсутствуют или неполные${NC}"
        IPTABLES_FORWARD_OK=false
    fi
    
    # Проверяем MASQUERADE
    local masquerade=$(iptables -t nat -L POSTROUTING -n -v 2>/dev/null | grep -c "MASQUERADE" || echo "0")
    
    if [ "$masquerade" -ge 1 ]; then
        echo -e "${GREEN}✓ Правило MASQUERADE настроено${NC}"
        IPTABLES_MASQUERADE_OK=true
        
        # Показываем детали
        echo -e "${BLUE}  Детали MASQUERADE:${NC}"
        iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE | head -1
    else
        echo -e "${RED}✗ Правило MASQUERADE отсутствует${NC}"
        IPTABLES_MASQUERADE_OK=false
    fi
    
    echo ""
}

# Функция проверки интерфейса WireGuard
check_wg_interface() {
    echo -e "${YELLOW}[3/4] Проверка интерфейса WireGuard...${NC}"
    
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        echo -e "${GREEN}✓ Интерфейс $WG_INTERFACE существует${NC}"
        
        local wg_status=$(ip link show "$WG_INTERFACE" | grep -o "state [A-Z]*" | awk '{print $2}')
        if [ "$wg_status" = "UP" ]; then
            echo -e "${GREEN}✓ Интерфейс $WG_INTERFACE поднят${NC}"
        else
            echo -e "${YELLOW}⚠ Интерфейс $WG_INTERFACE не поднят (state: $wg_status)${NC}"
        fi
        
        # Показываем IP адрес
        local wg_ip=$(ip addr show "$WG_INTERFACE" | grep "inet " | awk '{print $2}')
        if [ -n "$wg_ip" ]; then
            echo -e "${BLUE}  IP адрес: $wg_ip${NC}"
        fi
    else
        echo -e "${RED}✗ Интерфейс $WG_INTERFACE не найден${NC}"
        WG_INTERFACE_OK=false
    fi
    
    echo ""
}

# Функция определения внешнего интерфейса
detect_external_interface() {
    echo -e "${YELLOW}[4/4] Определение внешнего интерфейса...${NC}"
    
    # Пытаемся определить из конфигурации WireGuard
    if [ -f "$WG_CONF" ]; then
        local postup_line=$(grep "PostUp.*MASQUERADE" "$WG_CONF" | head -1)
        if [[ $postup_line =~ -o[[:space:]]+([a-zA-Z0-9]+) ]]; then
            EXTERNAL_INTERFACE="${BASH_REMATCH[1]}"
            echo -e "${GREEN}✓ Внешний интерфейс найден в конфигурации: $EXTERNAL_INTERFACE${NC}"
        fi
    fi
    
    # Если не нашли, пытаемся определить автоматически
    if [ -z "$EXTERNAL_INTERFACE" ]; then
        # Ищем интерфейс с маршрутом по умолчанию
        EXTERNAL_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
        if [ -n "$EXTERNAL_INTERFACE" ]; then
            echo -e "${GREEN}✓ Внешний интерфейс определен автоматически: $EXTERNAL_INTERFACE${NC}"
        else
            echo -e "${RED}✗ Не удалось определить внешний интерфейс${NC}"
            echo -e "${YELLOW}  Попробуйте указать вручную: ip route${NC}"
        fi
    fi
    
    echo ""
}

# Функция исправления IP forwarding
fix_ip_forwarding() {
    echo -e "${YELLOW}Исправление IP forwarding...${NC}"
    
    # Включаем временно
    sysctl -w net.ipv4.ip_forward=1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ IP forwarding включен временно${NC}"
    else
        echo -e "${RED}✗ Не удалось включить IP forwarding${NC}"
        return 1
    fi
    
    # Настраиваем постоянно
    if ! grep -q "^net.ipv4.ip_forward=1" "$SYSCTL_CONF" 2>/dev/null; then
        # Проверяем, есть ли закомментированная строка
        if grep -q "^#net.ipv4.ip_forward" "$SYSCTL_CONF" 2>/dev/null; then
            sed -i 's/^#net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' "$SYSCTL_CONF"
        else
            echo "net.ipv4.ip_forward=1" >> "$SYSCTL_CONF"
        fi
        echo -e "${GREEN}✓ IP forwarding настроен для постоянной работы${NC}"
    else
        echo -e "${GREEN}✓ IP forwarding уже настроен для постоянной работы${NC}"
    fi
    
    echo ""
}

# Функция исправления правил iptables
fix_iptables() {
    echo -e "${YELLOW}Исправление правил iptables...${NC}"
    
    # Проверяем и добавляем FORWARD правила
    if ! iptables -C FORWARD -i "$WG_INTERFACE" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$WG_INTERFACE" -j ACCEPT
        echo -e "${GREEN}✓ Добавлено правило: FORWARD -i $WG_INTERFACE -j ACCEPT${NC}"
    else
        echo -e "${GREEN}✓ Правило FORWARD -i $WG_INTERFACE уже существует${NC}"
    fi
    
    if ! iptables -C FORWARD -o "$WG_INTERFACE" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -o "$WG_INTERFACE" -j ACCEPT
        echo -e "${GREEN}✓ Добавлено правило: FORWARD -o $WG_INTERFACE -j ACCEPT${NC}"
    else
        echo -e "${GREEN}✓ Правило FORWARD -o $WG_INTERFACE уже существует${NC}"
    fi
    
    # Проверяем и добавляем MASQUERADE
    if [ -n "$EXTERNAL_INTERFACE" ]; then
        if ! iptables -t nat -C POSTROUTING -o "$EXTERNAL_INTERFACE" -j MASQUERADE 2>/dev/null; then
            iptables -t nat -A POSTROUTING -o "$EXTERNAL_INTERFACE" -j MASQUERADE
            echo -e "${GREEN}✓ Добавлено правило: MASQUERADE для $EXTERNAL_INTERFACE${NC}"
        else
            echo -e "${GREEN}✓ Правило MASQUERADE для $EXTERNAL_INTERFACE уже существует${NC}"
        fi
    else
        echo -e "${RED}✗ Не удалось определить внешний интерфейс для MASQUERADE${NC}"
        echo -e "${YELLOW}  Проверьте конфигурацию WireGuard: $WG_CONF${NC}"
    fi
    
    echo ""
}

# Функция сохранения правил iptables
save_iptables() {
    echo -e "${YELLOW}Сохранение правил iptables...${NC}"
    
    # Создаем директорию если не существует
    mkdir -p /etc/iptables
    
    # Сохраняем правила
    if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
        echo -e "${GREEN}✓ Правила iptables сохранены в /etc/iptables/rules.v4${NC}"
        
        # Проверяем, включен ли netfilter-persistent
        if systemctl is-enabled netfilter-persistent &>/dev/null; then
            echo -e "${GREEN}✓ netfilter-persistent включен для автозагрузки${NC}"
        else
            echo -e "${YELLOW}⚠ Включение netfilter-persistent для автозагрузки...${NC}"
            systemctl enable netfilter-persistent &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ netfilter-persistent включен${NC}"
            else
                echo -e "${YELLOW}⚠ Не удалось включить netfilter-persistent (может быть не установлен)${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Не удалось сохранить правила iptables${NC}"
    fi
    
    echo ""
}

# Основная функция диагностики
main() {
    # Инициализация переменных
    IP_FORWARDING_OK=false
    IP_FORWARDING_PERSISTENT=true
    IPTABLES_FORWARD_OK=false
    IPTABLES_MASQUERADE_OK=false
    WG_INTERFACE_OK=true
    EXTERNAL_INTERFACE=""
    
    # Выполняем проверки
    check_ip_forwarding
    check_iptables
    check_wg_interface
    detect_external_interface
    
    # Выводим сводку
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Сводка диагностики:${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    local issues_found=false
    
    if [ "$IP_FORWARDING_OK" = false ]; then
        echo -e "${RED}✗ IP forwarding выключен${NC}"
        issues_found=true
    fi
    
    if [ "$IP_FORWARDING_PERSISTENT" = false ]; then
        echo -e "${YELLOW}⚠ IP forwarding не настроен для постоянной работы${NC}"
        issues_found=true
    fi
    
    if [ "$IPTABLES_FORWARD_OK" = false ]; then
        echo -e "${RED}✗ Правила FORWARD для wg0 отсутствуют${NC}"
        issues_found=true
    fi
    
    if [ "$IPTABLES_MASQUERADE_OK" = false ]; then
        echo -e "${RED}✗ Правило MASQUERADE отсутствует${NC}"
        issues_found=true
    fi
    
    if [ "$WG_INTERFACE_OK" = false ]; then
        echo -e "${RED}✗ Интерфейс WireGuard не найден${NC}"
        issues_found=true
    fi
    
    if [ -z "$EXTERNAL_INTERFACE" ]; then
        echo -e "${RED}✗ Не удалось определить внешний интерфейс${NC}"
        issues_found=true
    fi
    
    if [ "$issues_found" = false ]; then
        echo -e "${GREEN}✓ Все проверки пройдены успешно!${NC}"
        echo ""
        echo -e "${BLUE}Если проблема сохраняется, проверьте:${NC}"
        echo "  1. Логи WireGuard: journalctl -u wg-quick@wg0 -n 50"
        echo "  2. Статус подключенных пиров: wg show"
        echo "  3. Маршрутизацию на клиенте: ip route"
        echo ""
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Обнаружены проблемы. Исправить автоматически? (y/n)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Исправление проблем...${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        
        # Исправляем проблемы
        if [ "$IP_FORWARDING_OK" = false ] || [ "$IP_FORWARDING_PERSISTENT" = false ]; then
            fix_ip_forwarding
        fi
        
        if [ "$IPTABLES_FORWARD_OK" = false ] || [ "$IPTABLES_MASQUERADE_OK" = false ]; then
            fix_iptables
        fi
        
        # Сохраняем правила
        save_iptables
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Исправления применены!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}Рекомендуется перезапустить WireGuard:${NC}"
        echo "  wg-quick down wg0 && wg-quick up wg0"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}Исправление отменено пользователем.${NC}"
        echo ""
        echo -e "${BLUE}Для ручного исправления выполните:${NC}"
        echo ""
        
        if [ "$IP_FORWARDING_OK" = false ]; then
            echo "  # Включить IP forwarding:"
            echo "  sysctl -w net.ipv4.ip_forward=1"
            echo "  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
            echo ""
        fi
        
        if [ "$IPTABLES_FORWARD_OK" = false ]; then
            echo "  # Добавить правила FORWARD:"
            echo "  iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT"
            echo "  iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT"
            echo ""
        fi
        
        if [ "$IPTABLES_MASQUERADE_OK" = false ] && [ -n "$EXTERNAL_INTERFACE" ]; then
            echo "  # Добавить MASQUERADE:"
            echo "  iptables -t nat -A POSTROUTING -o $EXTERNAL_INTERFACE -j MASQUERADE"
            echo ""
        fi
        
        echo "  # Сохранить правила:"
        echo "  iptables-save > /etc/iptables/rules.v4"
        echo ""
    fi
}

# Запуск скрипта
main "$@"

