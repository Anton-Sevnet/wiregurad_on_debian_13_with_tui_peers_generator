#!/bin/bash

###############################################################################
# Скрипт диагностики подключения клиента WireGuard
# Проверяет статус WireGuard, подключенные пиры и правила INPUT
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

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Диагностика подключения клиента WireGuard${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Функция проверки статуса WireGuard сервиса
check_wg_service() {
    echo -e "${YELLOW}[1/5] Проверка статуса WireGuard сервиса...${NC}"
    
    if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
        echo -e "${GREEN}✓ WireGuard сервис запущен${NC}"
    else
        echo -e "${RED}✗ WireGuard сервис не запущен${NC}"
        echo -e "${YELLOW}  Попытка запуска...${NC}"
        systemctl start "wg-quick@${WG_INTERFACE}" 2>/dev/null
        sleep 2
        if systemctl is-active --quiet "wg-quick@${WG_INTERFACE}" 2>/dev/null; then
            echo -e "${GREEN}✓ WireGuard сервис запущен${NC}"
        else
            echo -e "${RED}✗ Не удалось запустить WireGuard сервис${NC}"
            echo -e "${BLUE}  Логи: journalctl -u wg-quick@${WG_INTERFACE} -n 50${NC}"
        fi
    fi
    echo ""
}

# Функция проверки интерфейса WireGuard
check_wg_interface() {
    echo -e "${YELLOW}[2/5] Проверка интерфейса WireGuard...${NC}"
    
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        echo -e "${GREEN}✓ Интерфейс $WG_INTERFACE существует${NC}"
        
        local wg_status=$(ip link show "$WG_INTERFACE" | grep -o "state [A-Z]*" | awk '{print $2}')
        if [ "$wg_status" = "UP" ] || ip link show "$WG_INTERFACE" | grep -q "UP"; then
            echo -e "${GREEN}✓ Интерфейс $WG_INTERFACE поднят${NC}"
        else
            echo -e "${YELLOW}⚠ Интерфейс $WG_INTERFACE не поднят (state: $wg_status)${NC}"
            echo -e "${BLUE}  Попытка поднять интерфейс...${NC}"
            ip link set up dev "$WG_INTERFACE" 2>/dev/null
            sleep 1
            if ip link show "$WG_INTERFACE" | grep -q "UP"; then
                echo -e "${GREEN}✓ Интерфейс поднят${NC}"
            else
                echo -e "${RED}✗ Не удалось поднять интерфейс${NC}"
            fi
        fi
        
        local wg_ip=$(ip addr show "$WG_INTERFACE" | grep "inet " | awk '{print $2}')
        if [ -n "$wg_ip" ]; then
            echo -e "${BLUE}  IP адрес: $wg_ip${NC}"
        fi
    else
        echo -e "${RED}✗ Интерфейс $WG_INTERFACE не найден${NC}"
        echo -e "${YELLOW}  Попытка запуска WireGuard...${NC}"
        wg-quick up "$WG_INTERFACE" 2>/dev/null
        sleep 2
        if ip link show "$WG_INTERFACE" &>/dev/null; then
            echo -e "${GREEN}✓ Интерфейс создан${NC}"
        else
            echo -e "${RED}✗ Не удалось создать интерфейс${NC}"
        fi
    fi
    echo ""
}

# Функция проверки подключенных пиров
check_wg_peers() {
    echo -e "${YELLOW}[3/5] Проверка подключенных пиров...${NC}"
    
    local wg_output=$(wg show "$WG_INTERFACE" 2>/dev/null)
    if [ -z "$wg_output" ]; then
        echo -e "${RED}✗ Не удалось получить информацию о пирах${NC}"
        echo -e "${YELLOW}  WireGuard может быть не запущен${NC}"
    else
        echo -e "${BLUE}  Текущие пиры:${NC}"
        echo "$wg_output" | sed 's/^/  /'
        
        local peer_count=$(echo "$wg_output" | grep -c "peer:" || echo "0")
        if [ "$peer_count" -eq 0 ]; then
            echo -e "${YELLOW}⚠ Пиры не подключены${NC}"
        else
            echo -e "${GREEN}✓ Найдено пиров: $peer_count${NC}"
        fi
    fi
    echo ""
}

# Функция проверки правил INPUT для UDP порта
check_input_rules() {
    echo -e "${YELLOW}[4/5] Проверка правил INPUT для UDP порта...${NC}"
    
    # Определяем порт из конфигурации
    local listen_port=$(grep "^ListenPort" "$WG_CONF" 2>/dev/null | awk '{print $3}' | head -1)
    if [ -z "$listen_port" ]; then
        listen_port="47770"  # Значение по умолчанию
    fi
    
    echo -e "${BLUE}  Порт WireGuard: $listen_port${NC}"
    
    # Проверяем правило INPUT для UDP порта
    local input_rule=$(iptables -L INPUT -n -v 2>/dev/null | grep -E "udp.*dpt:$listen_port|udp.*$listen_port" || echo "")
    
    if [ -n "$input_rule" ]; then
        echo -e "${GREEN}✓ Правило INPUT для UDP порта $listen_port найдено${NC}"
        echo -e "${BLUE}  $input_rule${NC}"
    else
        echo -e "${RED}✗ Правило INPUT для UDP порта $listen_port не найдено${NC}"
        echo -e "${YELLOW}  Добавление правила...${NC}"
        iptables -A INPUT -p udp --dport "$listen_port" -j ACCEPT 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Правило добавлено${NC}"
            # Сохраняем правила
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
            echo -e "${GREEN}✓ Правила сохранены${NC}"
        else
            echo -e "${RED}✗ Не удалось добавить правило${NC}"
        fi
    fi
    echo ""
}

# Функция проверки логов WireGuard
check_wg_logs() {
    echo -e "${YELLOW}[5/5] Проверка последних логов WireGuard...${NC}"
    
    local logs=$(journalctl -u "wg-quick@${WG_INTERFACE}" -n 20 --no-pager 2>/dev/null)
    if [ -n "$logs" ]; then
        echo -e "${BLUE}  Последние записи логов:${NC}"
        echo "$logs" | tail -10 | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ Логи не найдены${NC}"
    fi
    echo ""
}

# Функция проверки публичного ключа сервера
check_server_public_key() {
    echo -e "${YELLOW}Проверка публичного ключа сервера...${NC}"
    
    local server_public_key=$(wg show "$WG_INTERFACE" public-key 2>/dev/null)
    if [ -n "$server_public_key" ]; then
        echo -e "${GREEN}✓ Публичный ключ сервера:${NC}"
        echo -e "${BLUE}  $server_public_key${NC}"
        echo ""
        echo -e "${YELLOW}Убедитесь, что в конфигурации клиента указан этот ключ в поле PublicKey${NC}"
    else
        echo -e "${RED}✗ Не удалось получить публичный ключ сервера${NC}"
    fi
    echo ""
}

# Основная функция
main() {
    check_wg_service
    check_wg_interface
    check_wg_peers
    check_input_rules
    check_wg_logs
    check_server_public_key
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Рекомендации:${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "1. Проверьте конфигурацию клиента:"
    echo "   - PublicKey сервера должен совпадать с выводом выше"
    echo "   - Endpoint должен быть: 80.233.165.55:47770"
    echo "   - AllowedIPs должен быть: 0.0.0.0/0"
    echo ""
    echo "2. Проверьте, что пир добавлен в конфигурацию сервера:"
    echo "   cat $WG_CONF | grep -A 3 'PublicKey'"
    echo ""
    echo "3. Если пир не подключен, проверьте логи на клиенте"
    echo ""
    echo "4. Перезапустите WireGuard на сервере:"
    echo "   wg-quick down $WG_INTERFACE && wg-quick up $WG_INTERFACE"
    echo ""
}

# Запуск скрипта
main "$@"

