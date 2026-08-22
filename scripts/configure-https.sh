#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_DIR="/opt/price-monitor"
readonly NGINX_DIR="${PROJECT_DIR}/nginx"
readonly WEBROOT_DIR="${PROJECT_DIR}/certbot/www"

readonly BOOTSTRAP_CONF="${NGINX_DIR}/bootstrap.conf"
readonly HTTPS_TEMPLATE="${NGINX_DIR}/default.conf.tftpl"
readonly ACTIVE_CONF="${NGINX_DIR}/active.conf"
readonly CANDIDATE_CONF="${NGINX_DIR}/active.conf.candidate"
readonly BACKUP_CONF="${NGINX_DIR}/active.conf.before-https"

readonly PRICE_MONITOR_CONFIG_DIR="/etc/price-monitor"
readonly PUBLIC_IP_FILE="${PRICE_MONITOR_CONFIG_DIR}/public-ip"
readonly CERTIFICATE_MODE_FILE="${PRICE_MONITOR_CONFIG_DIR}/certificate-mode"

readonly RELOAD_SCRIPT="/usr/local/sbin/reload-price-monitor-nginx.sh"

readonly DEPLOY_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
readonly DEPLOY_HOOK="${DEPLOY_HOOK_DIR}/10-reload-price-monitor-nginx"

readonly NGINX_CONTAINER="price-monitor-nginx"

LETSENCRYPT_EMAIL="$(
  printf '%s' "${1:-}" |
    tr --delete '\r\n'
)"

readonly LETSENCRYPT_EMAIL
readonly LETSENCRYPT_STAGING="${2:-true}"

log() {
  printf '[configure-https] [%s] %s\n' \
    "$(date --iso-8601=seconds)" \
    "$*"
}

fail() {
  log "ERRO: $*"
  exit 1
}

trap 'fail "Falha na linha ${LINENO}: ${BASH_COMMAND}"' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Este script precisa ser executado como root."
  fi
}

validate_arguments() {
  if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
    fail "Informe o email do Let's Encrypt."
  fi

  if [[ ! "${LETSENCRYPT_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    fail "Email do Let's Encrypt inválido."
  fi

  case "${LETSENCRYPT_STAGING}" in
    true | false)
      ;;
    *)
      fail "letsencrypt_staging deve ser true ou false."
      ;;
  esac
}

validate_commands() {
  local command_name

  for command_name in \
    awk \
    curl \
    docker \
    grep \
    install \
    python3 \
    sed \
    sort \
    timeout
  do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      fail "Comando obrigatório não encontrado: ${command_name}"
    fi
  done
}

prepare_directories() {
  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "${NGINX_DIR}" \
    "${WEBROOT_DIR}/.well-known/acme-challenge" \
    "${PRICE_MONITOR_CONFIG_DIR}" \
    "${DEPLOY_HOOK_DIR}" \
    /etc/letsencrypt

  [[ -f "${BOOTSTRAP_CONF}" ]] || \
    fail "Arquivo não encontrado: ${BOOTSTRAP_CONF}"

  [[ -f "${HTTPS_TEMPLATE}" ]] || \
    fail "Arquivo não encontrado: ${HTTPS_TEMPLATE}"

  [[ -f "${ACTIVE_CONF}" ]] || \
    fail "Configuração ativa não encontrada: ${ACTIVE_CONF}"

  [[ -x "${RELOAD_SCRIPT}" ]] || \
    fail "Script ausente ou sem permissão: ${RELOAD_SCRIPT}"
}

wait_for_nginx() {
  log "Aguardando o container ${NGINX_CONTAINER}."

  for _ in {1..60}; do
    if docker inspect \
      --format '{{.State.Running}}' \
      "${NGINX_CONTAINER}" 2>/dev/null |
      grep --quiet '^true$'
    then
      log "Container Nginx está em execução."
      return 0
    fi

    sleep 5
  done

  fail "Nginx não iniciou dentro do tempo esperado."
}

validate_acme_webroot() {
  readonly TEST_TOKEN="price-monitor-cloud-init-test"
  readonly TEST_FILE="${WEBROOT_DIR}/.well-known/acme-challenge/${TEST_TOKEN}"

  printf '%s\n' "${TEST_TOKEN}" > "${TEST_FILE}"

  log "Validando o caminho HTTP do desafio ACME."

  local response
  local acme_ready="false"

  for _ in {1..30}; do
    response="$(
      curl \
        --fail \
        --silent \
        --show-error \
        --max-time 5 \
        "http://127.0.0.1/.well-known/acme-challenge/${TEST_TOKEN}" \
        2>/dev/null ||
        true
    )"

    if [[ "${response}" == "${TEST_TOKEN}" ]]; then
      acme_ready="true"
      break
    fi

    sleep 2
  done

  rm -f "${TEST_FILE}"

  if [[ "${acme_ready}" != "true" ]]; then
    fail "O Nginx não está entregando o diretório do desafio ACME."
  fi

  log "Webroot ACME validado."
}

install_certbot() {
  if ! command -v snap >/dev/null 2>&1; then
    log "Instalando snapd."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install \
      --yes \
      --no-install-recommends \
      snapd
  fi

  systemctl enable --now snapd.socket

  timeout 180 snap wait system seed.loaded || true

  if ! snap list certbot >/dev/null 2>&1; then
    log "Instalando Certbot."

    snap install \
      --classic \
      certbot
  fi

  ln \
    --symbolic \
    --force \
    /snap/bin/certbot \
    /usr/local/bin/certbot
}

validate_certbot_version() {
  local certbot_version
  local lowest_version

  certbot_version="$(
    certbot --version |
      awk '{print $2}'
  )"

  log "Certbot instalado: ${certbot_version}"

  lowest_version="$(
    printf '%s\n' \
      "5.4.0" \
      "${certbot_version}" |
      sort --version-sort |
      head -n 1
  )"

  if [[ "${lowest_version}" != "5.4.0" ]]; then
    fail "É necessário Certbot 5.4.0 ou superior."
  fi
}

discover_public_ip() {
  local endpoint
  local candidate

  local -a endpoints=(
    "https://api.ipify.org"
    "https://checkip.amazonaws.com"
    "https://ifconfig.me/ip"
  )

  for endpoint in "${endpoints[@]}"; do
    candidate="$(
      curl \
        --ipv4 \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 5 \
        --max-time 10 \
        "${endpoint}" 2>/dev/null |
        tr --delete '[:space:]' ||
        true
    )"

    if python3 - "${candidate}" <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)

if address.version != 4:
    raise SystemExit(1)

if not address.is_global:
    raise SystemExit(1)
PY
    then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

install_deploy_hook() {
  install \
    --owner root \
    --group root \
    --mode 0755 \
    "${RELOAD_SCRIPT}" \
    "${DEPLOY_HOOK}"
}

issue_certificate() {
  local public_ip="$1"

  readonly CERTIFICATE_DIR="/etc/letsencrypt/live/${public_ip}"
  readonly FULLCHAIN_FILE="${CERTIFICATE_DIR}/fullchain.pem"
  readonly PRIVATE_KEY_FILE="${CERTIFICATE_DIR}/privkey.pem"

  local desired_mode
  local current_mode=""

  if [[ "${LETSENCRYPT_STAGING}" == "true" ]]; then
    desired_mode="staging"
  else
    desired_mode="production"
  fi

  if [[ -s "${CERTIFICATE_MODE_FILE}" ]]; then
    current_mode="$(
      tr --delete '[:space:]' < "${CERTIFICATE_MODE_FILE}"
    )"
  fi

  if [[ -s "${FULLCHAIN_FILE}" &&
        -s "${PRIVATE_KEY_FILE}" &&
        "${current_mode}" == "${desired_mode}" ]]; then
    log "Certificado ${desired_mode} já existe; emissão ignorada."
    return 0
  fi

  log "Solicitando certificado ${desired_mode} para ${public_ip}."

  local -a certbot_args=(
    certonly
    --non-interactive
    --agree-tos
    --email "${LETSENCRYPT_EMAIL}"
    --preferred-profile shortlived
    --webroot
    --webroot-path "${WEBROOT_DIR}"
    --ip-address "${public_ip}"
    --cert-name "${public_ip}"
  )

  if [[ "${LETSENCRYPT_STAGING}" == "true" ]]; then
    certbot_args+=(--staging)
  fi

  if [[ -n "${current_mode}" &&
        "${current_mode}" != "${desired_mode}" ]]; then
    log "Alterando certificado de ${current_mode} para ${desired_mode}."

    certbot_args+=(--force-renewal)
  fi

  certbot "${certbot_args[@]}"

  [[ -s "${FULLCHAIN_FILE}" ]] || \
    fail "Certificado não encontrado: ${FULLCHAIN_FILE}"

  [[ -s "${PRIVATE_KEY_FILE}" ]] || \
    fail "Chave privada não encontrada: ${PRIVATE_KEY_FILE}"

  printf '%s\n' "${desired_mode}" > "${CERTIFICATE_MODE_FILE}"

  chown root:root "${CERTIFICATE_MODE_FILE}"
  chmod 0644 "${CERTIFICATE_MODE_FILE}"

  log "Certificado ${desired_mode} emitido."
}

render_https_config() {
  local public_ip="$1"

  log "Renderizando configuração HTTPS."

  sed \
    "s/__PUBLIC_IP__/${public_ip}/g" \
    "${HTTPS_TEMPLATE}" \
    > "${CANDIDATE_CONF}"

  chmod 0644 "${CANDIDATE_CONF}"

  cp \
    --preserve=mode,ownership \
    "${ACTIVE_CONF}" \
    "${BACKUP_CONF}"

  #
  # Sobrescreve o conteúdo do mesmo inode utilizado
  # pelo bind mount do container.
  #
  cat "${CANDIDATE_CONF}" > "${ACTIVE_CONF}"

  rm -f "${CANDIDATE_CONF}"
}

activate_https_config() {
  log "Validando configuração HTTPS do Nginx."

  if ! docker exec \
    "${NGINX_CONTAINER}" \
    nginx -t
  then
    log "Configuração HTTPS inválida; restaurando bootstrap HTTP."

    cat "${BACKUP_CONF}" > "${ACTIVE_CONF}"

    docker exec \
      "${NGINX_CONTAINER}" \
      nginx -t

    docker exec \
      "${NGINX_CONTAINER}" \
      nginx -s reload

    fail "A configuração HTTPS foi rejeitada pelo Nginx."
  fi

  log "Recarregando o Nginx com HTTPS."

  docker exec \
    "${NGINX_CONTAINER}" \
    nginx -s reload
}

validate_https_and_auth() {
  log "Validando HTTPS e Basic Auth."

  local http_status
  local https_ready="false"

  for _ in {1..30}; do
    http_status="$(
      curl \
        --insecure \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        --header "Host: $(cat "${PUBLIC_IP_FILE}")" \
        --max-time 5 \
        https://127.0.0.1/ \
        2>/dev/null ||
        true
    )"

    #
    # Sem credenciais, o resultado correto é 401.
    # Isso confirma que HTTPS e Basic Auth estão ativos.
    #
    if [[ "${http_status}" == "401" ]]; then
      https_ready="true"
      break
    fi

    sleep 2
  done

  if [[ "${https_ready}" != "true" ]]; then
    fail "HTTPS não respondeu com o 401 esperado do Basic Auth."
  fi

  log "HTTPS e Basic Auth validados com sucesso."
}

show_certbot_timer() {
  log "Timers relacionados ao Certbot:"

  systemctl list-timers \
    --all \
    --no-pager |
    grep --ignore-case certbot ||
    log "Timer do Certbot não foi localizado automaticamente."
}

main() {
  require_root
  validate_arguments
  validate_commands
  prepare_directories

  wait_for_nginx
  validate_acme_webroot

  install_certbot
  validate_certbot_version

  local public_ip

  public_ip="$(discover_public_ip)" || \
    fail "Não foi possível descobrir o IPv4 público."

  readonly public_ip

  log "IPv4 público detectado: ${public_ip}"

  printf '%s\n' "${public_ip}" > "${PUBLIC_IP_FILE}"

  chown root:root "${PUBLIC_IP_FILE}"
  chmod 0644 "${PUBLIC_IP_FILE}"

  install_deploy_hook
  issue_certificate "${public_ip}"
  render_https_config "${public_ip}"
  activate_https_config
  validate_https_and_auth
  show_certbot_timer

  log "HTTPS/TLS configurado com sucesso."
  log "Acesso: https://${public_ip}"

  if [[ "${LETSENCRYPT_STAGING}" == "true" ]]; then
    log "ATENÇÃO: certificado de staging não é confiável no navegador."
  fi
}

main "$@"