#!/bin/bash

###############################################################################
# Скрипт для принудительного применения правил FORWARD для WireGuard
# Используется когда правила не применяются автоматически
###############################################################################

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

WG_INTERFACE="wg0"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Этот скрипт должен запускаться от root${NC}"
    exit 1
fi

echo -e "${BLUE}Принудительное применение правил FORWARD для $WG_INTERFACE${NC}"
echo ""

# Определяем внешний интерфейс
EXTERNAL_INTERFACE=""
if [ -f "/etc/wireguard/wg0.conf" ]; then
    EXTERNAL_INTERFACE=$(grep "PostUp.*MASQUERADE" /etc/wireguard/wg0.conf | grep -oE "-o[[:space:]]+[a-zA-Z0-9]+" | awk '{print $2}' | head -1)
fi

if [ -z "$EXTERNAL_INTERFACE" ]; then
    EXTERNAL_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
fi

if [ -z "$EXTERNAL_INTERFACE" ]; then
    echo -e "${RED}Ошибка: Не удалось определить внешний интерфейс${NC}"
    exit 1
fi

echo -e "${BLUE}Внешний интерфейс: $EXTERNAL_INTERFACE${NC}"
echo ""

# Удаляем все существующие правила для wg0 в INPUT
echo -e "${YELLOW}Удаление старых правил INPUT для $WG_INTERFACE...${NC}"
while iptables -D INPUT -i "$WG_INTERFACE" -j ACCEPT 2>/dev/null; do
    echo -e "${BLUE}  Удалено: INPUT -i $WG_INTERFACE${NC}"
done

# Добавляем INPUT правило
echo ""
echo -e "${YELLOW}Добавление правила INPUT...${NC}"

iptables -A INPUT -i "$WG_INTERFACE" -j ACCEPT
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Добавлено: INPUT -i $WG_INTERFACE -j ACCEPT${NC}"
else
    echo -e "${RED}✗ Ошибка при добавлении правила INPUT -i $WG_INTERFACE${NC}"
    exit 1
fi

# Удаляем все существующие правила для wg0 в FORWARD
echo ""
echo -e "${YELLOW}Удаление старых правил FORWARD для $WG_INTERFACE...${NC}"
while iptables -D FORWARD -i "$WG_INTERFACE" -j ACCEPT 2>/dev/null; do
    echo -e "${BLUE}  Удалено: FORWARD -i $WG_INTERFACE${NC}"
done

while iptables -D FORWARD -o "$WG_INTERFACE" -j ACCEPT 2>/dev/null; do
    echo -e "${BLUE}  Удалено: FORWARD -o $WG_INTERFACE${NC}"
done

# Добавляем правила заново
echo ""
echo -e "${YELLOW}Добавление правил FORWARD...${NC}"

iptables -A FORWARD -i "$WG_INTERFACE" -j ACCEPT
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Добавлено: FORWARD -i $WG_INTERFACE -j ACCEPT${NC}"
else
    echo -e "${RED}✗ Ошибка при добавлении правила FORWARD -i $WG_INTERFACE${NC}"
    exit 1
fi

iptables -A FORWARD -o "$WG_INTERFACE" -j ACCEPT
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Добавлено: FORWARD -o $WG_INTERFACE -j ACCEPT${NC}"
else
    echo -e "${RED}✗ Ошибка при добавлении правила FORWARD -o $WG_INTERFACE${NC}"
    exit 1
fi

# Проверяем MASQUERADE
echo ""
echo -e "${YELLOW}Проверка правила MASQUERADE...${NC}"

# Удаляем старое правило MASQUERADE если есть
while iptables -t nat -D POSTROUTING -o "$EXTERNAL_INTERFACE" -j MASQUERADE 2>/dev/null; do
    echo -e "${BLUE}  Удалено старое правило MASQUERADE${NC}"
done

# Добавляем правило MASQUERADE
iptables -t nat -A POSTROUTING -o "$EXTERNAL_INTERFACE" -j MASQUERADE
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Добавлено: MASQUERADE для $EXTERNAL_INTERFACE${NC}"
else
    echo -e "${RED}✗ Ошибка при добавлении правила MASQUERADE${NC}"
    exit 1
fi

# Проверяем результат
echo ""
echo -e "${YELLOW}Проверка примененных правил...${NC}"

check_input=$(iptables-save 2>/dev/null | grep -c "^-A INPUT.*-i $WG_INTERFACE.*-j ACCEPT" || echo "0")
check_in=$(iptables-save 2>/dev/null | grep -c "^-A FORWARD.*-i $WG_INTERFACE.*-j ACCEPT" || echo "0")
check_out=$(iptables-save 2>/dev/null | grep -c "^-A FORWARD.*-o $WG_INTERFACE.*-j ACCEPT" || echo "0")
check_masq=$(iptables-save 2>/dev/null | grep -c "^-A POSTROUTING.*-o $EXTERNAL_INTERFACE.*-j MASQUERADE" || echo "0")

if [ "$check_input" -ge 1 ] && [ "$check_in" -ge 1 ] && [ "$check_out" -ge 1 ] && [ "$check_masq" -ge 1 ]; then
    echo -e "${GREEN}✓ Все правила успешно применены!${NC}"
    echo ""
    echo -e "${BLUE}Текущие правила INPUT для wg0:${NC}"
    iptables -L INPUT -n -v | grep -E "(wg0|Chain|target)" | head -5
    echo ""
    echo -e "${BLUE}Текущие правила FORWARD:${NC}"
    iptables -L FORWARD -n -v | grep -E "(wg0|Chain|target)"
    echo ""
    echo -e "${BLUE}Текущие правила MASQUERADE:${NC}"
    iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE
else
    echo -e "${RED}✗ Проверка показала проблемы (input=$check_input, in=$check_in, out=$check_out, masq=$check_masq)${NC}"
    exit 1
fi

# Сохраняем правила
echo ""
echo -e "${YELLOW}Сохранение правил...${NC}"
mkdir -p /etc/iptables
if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
    echo -e "${GREEN}✓ Правила сохранены в /etc/iptables/rules.v4${NC}"
else
    echo -e "${RED}✗ Ошибка при сохранении правил${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Готово! Правила применены и сохранены.${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Рекомендуется перезапустить WireGuard:${NC}"
echo "  wg-quick down wg0 && wg-quick up wg0"
echo ""

