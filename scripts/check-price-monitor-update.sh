#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

readonly PROJECT_DIR="/opt/price-monitor"
readonly ENV_FILE="${PROJECT_DIR}/.env"

readonly DASHBOARD_IMAGE="ghcr.io/sc4rlxrd/price-monitor-dashboard"
readonly COLLECTOR_IMAGE="ghcr.io/sc4rlxrd/price-monitor-collector"

readonly DEPLOY_SCRIPT="/usr/local/sbin/deploy-price-monitor.sh"
readonly LOG_TAG="price-monitor-update"

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

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Este script deve ser executado como root."
  fi
}

validate_environment() {
  command -v docker >/dev/null 2>&1 || \
    fail "Docker não foi encontrado."

  [[ -x "${DEPLOY_SCRIPT}" ]] || \
    fail "Script ${DEPLOY_SCRIPT} não existe ou não é executável."
}

collector_is_running() {
  systemctl is-active \
    --quiet \
    price-monitor-collector.service
}

current_image_tag() {
  local current_image

  if [[ -f "${ENV_FILE}" ]]; then
    current_image="$(
      sed -n 's/^IMAGE_TAG=//p' "${ENV_FILE}" |
        tail -n 1
    )"

    if [[ -n "${current_image}" ]]; then
      printf '%s\n' "${current_image}"
      return
    fi
  fi

  current_image="$(
    docker inspect \
      price-monitor-dashboard \
      --format '{{.Config.Image}}' \
      2>/dev/null || true
  )"

  if [[ "${current_image}" == *:* ]]; then
    printf '%s\n' "${current_image##*:}"
    return
  fi

  printf '%s\n' ""
}

image_revision() {
  local image="$1"

  docker image inspect \
    "${image}" \
    --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
}

main() {
  require_root
  validate_environment

  #
  # A coleta é mais importante.
  # Se o Selenium estiver trabalhando, esperamos a próxima checagem.
  #
  if collector_is_running; then
    log "Collector em execução; verificação de atualização adiada."
    exit 0
  fi

  local current_tag
  local dashboard_revision
  local collector_revision
  local new_tag

  current_tag="$(current_image_tag)"

  log "Consultando versão mais recente do Dashboard..."

  docker pull \
    "${DASHBOARD_IMAGE}:latest" \
    >/dev/null

  log "Consultando versão mais recente do Collector..."

  docker pull \
    "${COLLECTOR_IMAGE}:latest" \
    >/dev/null

  dashboard_revision="$(
    image_revision "${DASHBOARD_IMAGE}:latest"
  )"

  collector_revision="$(
    image_revision "${COLLECTOR_IMAGE}:latest"
  )"

  if [[ ! "${dashboard_revision}" =~ ^[0-9a-f]{40}$ ]]; then
    fail "Revision inválida no Dashboard: ${dashboard_revision:-<vazia>}"
  fi

  if [[ ! "${collector_revision}" =~ ^[0-9a-f]{40}$ ]]; then
    fail "Revision inválida no Collector: ${collector_revision:-<vazia>}"
  fi

  if [[ "${dashboard_revision}" != "${collector_revision}" ]]; then
    log "Dashboard e Collector ainda não apontam para a mesma revisão."
    log "Dashboard: ${dashboard_revision}"
    log "Collector: ${collector_revision}"
    log "Deploy adiado até a próxima verificação."
    exit 0
  fi

  new_tag="sha-${dashboard_revision:0:7}"

  log "Versão em produção: ${current_tag:-desconhecida}"
  log "Versão disponível: ${new_tag}"

  if [[ "${current_tag}" == "${new_tag}" ]]; then
    log "Price Monitor já está atualizado."
    exit 0
  fi

  log "Nova versão detectada."

  "${DEPLOY_SCRIPT}" "${new_tag}"
}

main "$@"