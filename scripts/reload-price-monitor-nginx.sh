#!/usr/bin/env bash

set -Eeuo pipefail

readonly NGINX_CONTAINER="price-monitor-nginx"
readonly LOG_TAG="price-monitor-nginx-reload"

log() {
  logger \
    --tag "${LOG_TAG}" \
    -- "$*"

  printf '[%s] %s\n' \
    "$(date --iso-8601=seconds)" \
    "$*"
}

fail() {
  log "ERRO: $*"
  exit 1
}

if ! command -v docker >/dev/null 2>&1; then
  fail "Docker não foi encontrado."
fi

if ! docker inspect \
  --format '{{.State.Running}}' \
  "${NGINX_CONTAINER}" 2>/dev/null |
  grep --quiet '^true$'; then

  log "O container ${NGINX_CONTAINER} não está em execução; reload ignorado."
  exit 0
fi

log "Validando a configuração do Nginx."

docker exec \
  "${NGINX_CONTAINER}" \
  nginx -t

log "Recarregando o Nginx."

docker exec \
  "${NGINX_CONTAINER}" \
  nginx -s reload

log "Nginx recarregado com sucesso."