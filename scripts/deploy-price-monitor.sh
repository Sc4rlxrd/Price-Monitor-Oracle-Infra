#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

readonly PROJECT_DIR="/opt/price-monitor"
readonly COMPOSE_FILE="${PROJECT_DIR}/compose.yaml"
readonly ENV_FILE="${PROJECT_DIR}/.env"

readonly DASHBOARD_IMAGE="ghcr.io/sc4rlxrd/price-monitor-dashboard"
readonly COLLECTOR_IMAGE="ghcr.io/sc4rlxrd/price-monitor-collector"

readonly OPERATION_LOCK_FILE="/run/lock/price-monitor-operation.lock"
readonly LOG_TAG="price-monitor-deploy"

readonly IMAGE_TAG="${1:-}"

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

validate_image_tag() {
  if [[ ! "${IMAGE_TAG}" =~ ^sha-[0-9a-f]{7}$ ]]; then
    fail "Tag inválida: ${IMAGE_TAG:-<vazia>}"
  fi
}

validate_environment() {
  command -v docker >/dev/null 2>&1 || \
    fail "Docker não foi encontrado."

  docker compose version >/dev/null 2>&1 || \
    fail "Docker Compose não foi encontrado."

  [[ -d "${PROJECT_DIR}" ]] || \
    fail "O diretório ${PROJECT_DIR} não existe."

  [[ -f "${COMPOSE_FILE}" ]] || \
    fail "O arquivo ${COMPOSE_FILE} não existe."
}

acquire_operation_lock() {
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "$(dirname "${OPERATION_LOCK_FILE}")"

  exec 8>"${OPERATION_LOCK_FILE}"

  if ! flock --nonblock 8; then
    log "Collector ou outro deploy está em execução; atualização adiada."
    exit 0
  fi
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

write_image_tag() {
  local tag="$1"
  local temporary_file

  temporary_file="$(mktemp)"

  if [[ -f "${ENV_FILE}" ]]; then
    grep -v '^IMAGE_TAG=' "${ENV_FILE}" \
      > "${temporary_file}" || true
  fi

  printf 'IMAGE_TAG=%s\n' "${tag}" \
    >> "${temporary_file}"

  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${temporary_file}" \
    "${ENV_FILE}"

  rm -f "${temporary_file}"
}

compose() {
  if [[ -f "${ENV_FILE}" ]]; then
    docker compose \
      --env-file "${ENV_FILE}" \
      --file "${COMPOSE_FILE}" \
      "$@"
  else
    docker compose \
      --file "${COMPOSE_FILE}" \
      "$@"
  fi
}

pull_new_images() {
  log "Baixando Dashboard ${IMAGE_TAG}..."
  docker pull "${DASHBOARD_IMAGE}:${IMAGE_TAG}"

  log "Baixando Collector ${IMAGE_TAG}..."
  docker pull "${COLLECTOR_IMAGE}:${IMAGE_TAG}"
}

validate_compose() {
  log "Validando Docker Compose..."

  compose \
    --profile collector \
    config \
    --quiet
}

deploy_dashboard() {
  log "Atualizando Dashboard para ${IMAGE_TAG}..."

  compose \
    up \
    --detach \
    --no-deps \
    dashboard
}

wait_for_dashboard() {
  local status=""

  log "Aguardando Dashboard ficar saudável..."

  for _ in $(seq 1 30); do
    status="$(
      docker inspect \
        price-monitor-dashboard \
        --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
        2>/dev/null || true
    )"

    case "${status}" in
      healthy)
        log "Dashboard saudável."
        return 0
        ;;

      running)
        log "Dashboard em execução."
        return 0
        ;;

      unhealthy | exited | dead)
        log "Dashboard apresentou estado ${status}."
        return 1
        ;;
    esac

    sleep 3
  done

  log "Timeout aguardando o Dashboard."
  return 1
}

rollback() {
  local previous_tag="$1"

  if [[ -z "${previous_tag}" ]]; then
    log "Não foi possível determinar a versão anterior para rollback."
    return 1
  fi

  log "Executando rollback para ${previous_tag}..."

  write_image_tag "${previous_tag}"

  compose \
    up \
    --detach \
    --no-deps \
    dashboard

  wait_for_dashboard
}

cleanup_old_version() {
  local previous_tag="$1"

  if [[ -z "${previous_tag}" ]] ||
     [[ "${previous_tag}" == "${IMAGE_TAG}" ]] ||
     [[ ! "${previous_tag}" =~ ^sha-[0-9a-f]{7}$ ]]; then
    return
  fi

  log "Removendo imagens antigas ${previous_tag}..."

  docker image rm \
    "${DASHBOARD_IMAGE}:${previous_tag}" \
    "${COLLECTOR_IMAGE}:${previous_tag}" \
    >/dev/null 2>&1 || true

  docker image prune --force >/dev/null
}

show_status() {
  log "Estado atual dos containers:"

  compose ps
}

main() {
  require_root
  validate_image_tag
  validate_environment
  acquire_operation_lock

  local previous_tag

  previous_tag="$(current_image_tag)"

  if [[ "${previous_tag}" == "${IMAGE_TAG}" ]]; then
    log "A versão ${IMAGE_TAG} já está em produção."
    exit 0
  fi

  log "Versão atual: ${previous_tag:-desconhecida}"
  log "Nova versão: ${IMAGE_TAG}"

  #
  # Primeiro baixa as duas imagens.
  # A versão da produção só muda se ambas existirem.
  #
  pull_new_images

  write_image_tag "${IMAGE_TAG}"

  validate_compose

  if ! deploy_dashboard || ! wait_for_dashboard; then
    log "Falha durante o deploy."

    if rollback "${previous_tag}"; then
      log "Rollback concluído para ${previous_tag}."
    else
      log "ERRO: rollback também falhou."
    fi

    exit 1
  fi

  cleanup_old_version "${previous_tag}"
  show_status

  log "Deploy ${IMAGE_TAG} concluído com sucesso."
}

main "$@"