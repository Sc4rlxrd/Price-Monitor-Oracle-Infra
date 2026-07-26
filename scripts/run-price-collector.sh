#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

readonly PROJECT_DIR="/opt/price-monitor"
readonly COMPOSE_FILE="${PROJECT_DIR}/compose.yaml"
readonly DATA_DIR="${PROJECT_DIR}/data"

readonly JSON_FILE="${DATA_DIR}/precos.json"
readonly H2_FILE="${DATA_DIR}/price-monitor.mv.db"

readonly LOCK_FILE="/run/lock/price-monitor-collector.lock"
readonly LOG_TAG="price-monitor-collector"

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

  docker compose version >/dev/null 2>&1 || \
    fail "Docker Compose não foi encontrado."

  [[ -d "${PROJECT_DIR}" ]] || \
    fail "O diretório ${PROJECT_DIR} não existe."

  [[ -f "${COMPOSE_FILE}" ]] || \
    fail "O arquivo ${COMPOSE_FILE} não existe."

  [[ -f "${PROJECT_DIR}/config/urls.txt" ]] || \
    fail "O arquivo config/urls.txt não existe."

  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "${DATA_DIR}"
}

acquire_lock() {
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "$(dirname "${LOCK_FILE}")"

  exec 9>"${LOCK_FILE}"

  if ! flock --nonblock 9; then
    log "Já existe uma coleta em execução; nova execução ignorada."
    exit 0
  fi
}

restore_application() {
  local original_exit_code=$?

  trap - EXIT INT TERM
  set +e

  log "Restaurando dashboard e Nginx."

  docker compose \
    --file "${COMPOSE_FILE}" \
    up \
    --detach \
    dashboard \
    nginx

  local restore_exit_code=$?

  if [[ "${restore_exit_code}" -ne 0 ]]; then
    log "ERRO: não foi possível restaurar dashboard e Nginx."

    if [[ "${original_exit_code}" -eq 0 ]]; then
      original_exit_code="${restore_exit_code}"
    fi
  else
    log "Dashboard e Nginx restaurados."
  fi

  exit "${original_exit_code}"
}

stop_application() {
  log "Parando Nginx e dashboard para liberar memória."

  docker compose \
    --file "${COMPOSE_FILE}" \
    stop \
    --timeout 30 \
    nginx \
    dashboard
}

run_collector() {
  log "Iniciando o collector."

  docker compose \
    --file "${COMPOSE_FILE}" \
    --profile collector \
    run \
    --rm \
    --no-deps \
    collector

  log "Collector finalizado com sucesso."
}

validate_outputs() {
  [[ -s "${JSON_FILE}" ]] || \
    fail "O collector não gerou um arquivo JSON válido em ${JSON_FILE}."

  [[ -s "${H2_FILE}" ]] || \
    fail "O banco H2 não foi encontrado em ${H2_FILE}."

  log "Arquivos persistentes validados."

  log "JSON: $(du -h "${JSON_FILE}" | cut -f1)"
  log "H2: $(du -h "${H2_FILE}" | cut -f1)"
}

show_status() {
  log "Estado final dos serviços:"

  docker compose \
    --file "${COMPOSE_FILE}" \
    ps
}

main() {
  require_root
  validate_environment
  acquire_lock

  trap restore_application EXIT INT TERM

  log "Iniciando rotina de coleta do Price Monitor."

  stop_application
  run_collector
  validate_outputs

  log "Rotina de coleta concluída."

  #
  # O trap EXIT restaura dashboard e Nginx.
  #
}

main "$@"