#!/usr/bin/env bash

set -Eeuo pipefail

export LC_ALL=C

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN não definido}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID não definido}"

HOSTNAME="$(hostname --short)"

CPU="$(
    top -bn1 |
        awk '/Cpu\(s\)/ {
            printf "%.0f%%", 100 - $8
            exit
        }'
)"

RAM="$(
    free |
        awk '/Mem:/ {
            printf "%.0f%%", (($2 - $7) / $2) * 100
        }'
)"

SWAP="$(
    free |
        awk '/Swap:/ {
            if ($2 == 0) {
                print "0%"
            } else {
                printf "%.0f%%", ($3 / $2) * 100
            }
        }'
)"

DISK="$(
    df -P / |
        awk 'NR == 2 {
            print $5
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

MESSAGE="🖥️ [ORACLE VM]

🟢 ${HOSTNAME} online

CPU: ${CPU}
RAM: ${RAM}
Swap: ${SWAP}
Disco: ${DISK}
Load: ${LOAD_AVERAGE}
Uptime: ${UPTIME}"

curl \
    --fail \
    --silent \
    --show-error \
    --connect-timeout 10 \
    --max-time 20 \
    --retry 2 \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${MESSAGE}"