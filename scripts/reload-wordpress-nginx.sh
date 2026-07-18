#!/usr/bin/env bash

set -Eeuo pipefail

readonly DOCKER_BIN="/usr/bin/docker"
readonly NGINX_CONTAINER="wordpress-nginx"
readonly LOG_TAG="certbot-nginx-reload"

log() {
    logger \
        --tag "${LOG_TAG}" \
        -- "$*"

    printf '[%s] %s\n' \
        "$(date --iso-8601=seconds)" \
        "$*"
}

if [[ ! -x "${DOCKER_BIN}" ]]; then
    log "Docker não encontrado em ${DOCKER_BIN}."
    exit 1
fi

#
# Caso o container esteja parado, não há necessidade de iniciá-lo
# somente por causa do hook. Quando ele subir novamente, lerá o
# certificado atualizado do volume montado.
#
if ! "${DOCKER_BIN}" inspect \
    --format '{{.State.Running}}' \
    "${NGINX_CONTAINER}" 2>/dev/null |
    grep --quiet '^true$'; then

    log "Container ${NGINX_CONTAINER} não está em execução; reload ignorado."
    exit 0
fi

log "Validando configuração do Nginx."

"${DOCKER_BIN}" exec \
    "${NGINX_CONTAINER}" \
    nginx -t

log "Recarregando Nginx após renovação do certificado."

"${DOCKER_BIN}" exec \
    "${NGINX_CONTAINER}" \
    nginx -s reload

log "Nginx recarregado com sucesso."