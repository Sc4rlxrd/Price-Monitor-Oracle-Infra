#!/usr/bin/env bash

set -Eeuo pipefail

export LC_ALL=C

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN não definido}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID não definido}"

HOSTNAME="$(hostname --short)"

# --- CPU ---
CPU_PCT="$(
    top -bn1 |
        awk '/Cpu\(s\)/ {
            printf "%.0f", 100 - $8
        }'
)"

# --- RAM (percentual + valores absolutos em MB) ---
read -r RAM_PCT RAM_USED_MB RAM_TOTAL_MB <<< "$(
    free -m |
        awk '/Mem:/ {
            used = $2 - $7
            printf "%.0f %d %d", (used / $2) * 100, used, $2
        }'
)"

# --- Swap ---
SWAP_PCT="$(
    free |
        awk '/Swap:/ {
            if ($2 == 0) {
                print "0"
            } else {
                printf "%.0f", ($3 / $2) * 100
            }
        }'
)"

# --- Disco (percentual + valores absolutos) ---
read -r DISK_PCT DISK_USED DISK_TOTAL <<< "$(
    df -Ph / |
        awk 'NR == 2 {
            gsub("%", "", $5)
            print $5, $3, $2
        }'
)"

UPTIME="$(
    uptime -p |
        sed 's/^up //'
)"

LOAD_AVERAGE="$(
    awk '{
        print $1, $2, $3
    }' /proc/loadavg
)"

# --- IP público ---
PUBLIC_IP="$(
    curl --silent --max-time 5 https://ifconfig.me || echo "indisponível"
)"

TIMESTAMP="$(date '+%d/%m/%Y %H:%M:%S')"

# --- Define o emoji de status geral conforme os thresholds ---
STATUS_EMOJI="🟢"
if [ "${CPU_PCT}" -ge 90 ] || [ "${RAM_PCT}" -ge 90 ] || [ "${DISK_PCT}" -ge 90 ]; then
    STATUS_EMOJI="🔴"
elif [ "${CPU_PCT}" -ge 75 ] || [ "${RAM_PCT}" -ge 75 ] || [ "${DISK_PCT}" -ge 80 ]; then
    STATUS_EMOJI="🟡"
fi

MESSAGE="🖥️ [ORACLE VM]

${STATUS_EMOJI} ${HOSTNAME} online
🌐 IP: ${PUBLIC_IP}

CPU: ${CPU_PCT}%
RAM: ${RAM_PCT}% (${RAM_USED_MB}MB/${RAM_TOTAL_MB}MB)
Swap: ${SWAP_PCT}%
Disco: ${DISK_PCT}% (${DISK_USED}/${DISK_TOTAL})
Load: ${LOAD_AVERAGE}
Uptime: ${UPTIME}

🕐 ${TIMESTAMP}"

curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 10 \
    --max-time 20 \
    --retry 2 \
    --retry-delay 2 \
    --retry-all-errors \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}"