#!/usr/bin/env bash

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly PROJECT_DIR="/opt/price-monitor"
readonly COMPOSE_FILE="${PROJECT_DIR}/compose.yaml"

readonly NGINX_DIR="${PROJECT_DIR}/nginx"
readonly AUTH_DIR="${NGINX_DIR}/auth"
readonly AUTH_FILE="${AUTH_DIR}/.htpasswd"
readonly ACTIVE_NGINX_CONFIG="${NGINX_DIR}/active.conf"
readonly BOOTSTRAP_NGINX_CONFIG="${NGINX_DIR}/bootstrap.conf"

readonly INITIAL_PASSWORD_FILE="/root/price-monitor-initial-password.txt"

readonly AUTH_USERNAME="${1:-guilherme}"

log() {
  printf '[bootstrap-price-monitor] %s\n' "$*"
}

fail() {
  printf '[bootstrap-price-monitor] ERRO: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Este script deve ser executado como root."
  fi
}

validate_auth_username() {
  if [[ ! "${AUTH_USERNAME}" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    fail "O usuário do Basic Auth contém caracteres inválidos."
  fi
}

configure_swap() {
  log "Configurando swap de 2 GB..."

  if [[ ! -f /swapfile ]]; then
    if ! fallocate -l 2G /swapfile; then
      dd \
        if=/dev/zero \
        of=/swapfile \
        bs=1M \
        count=2048 \
        status=progress
    fi

    chmod 0600 /swapfile
    mkswap /swapfile
  fi

  if ! swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
    swapon /swapfile
  fi

  if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab; then
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  fi
}

install_base_packages() {
  log "Instalando dependências básicas..."

  apt-get update

  apt-get install \
    --yes \
    --no-install-recommends \
    ca-certificates \
    curl \
    openssl
}

validate_cloud_init_packages() {
  log "Validando os pacotes instalados pelo cloud-init..."

  command -v htpasswd >/dev/null 2>&1 || \
    fail "O apache2-utils não foi instalado pelo cloud-init."

  command -v openssl >/dev/null 2>&1 || \
    fail "O OpenSSL não está instalado."
}

configure_docker_repository() {
  log "Configurando o repositório oficial do Docker..."

  install \
    --directory \
    --mode 0755 \
    /etc/apt/keyrings

  curl \
    --fail \
    --silent \
    --show-error \
    --location \
    https://download.docker.com/linux/ubuntu/gpg \
    --output /etc/apt/keyrings/docker.asc

  chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ -z "${VERSION_CODENAME:-}" ]]; then
    fail "Não foi possível identificar a versão do Ubuntu."
  fi

  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

install_docker() {
  log "Instalando Docker Engine e Docker Compose..."

  configure_docker_repository

  apt-get update

  apt-get install \
    --yes \
    --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable --now docker

  usermod -aG docker ubuntu || true

  docker version >/dev/null
  docker compose version >/dev/null
}

prepare_directories() {
  log "Preparando os diretórios do Price Monitor..."

  install \
    --directory \
    --owner root \
    --group root \
    --mode 0755 \
    "${PROJECT_DIR}" \
    "${PROJECT_DIR}/config" \
    "${PROJECT_DIR}/data" \
    "${NGINX_DIR}" \
    "${AUTH_DIR}" \
    "${PROJECT_DIR}/certbot" \
    "${PROJECT_DIR}/certbot/www"

  [[ -f "${COMPOSE_FILE}" ]] || \
    fail "O arquivo ${COMPOSE_FILE} não foi provisionado."

  [[ -f "${PROJECT_DIR}/config/urls.txt" ]] || \
    fail "O arquivo config/urls.txt não foi provisionado."

  [[ -f "${BOOTSTRAP_NGINX_CONFIG}" ]] || \
    fail "A configuração bootstrap do Nginx não foi provisionada."

  [[ -f "${NGINX_DIR}/default.conf.tftpl" ]] || \
    fail "O template HTTPS do Nginx não foi provisionado."

  chmod 0644 \
    "${COMPOSE_FILE}" \
    "${PROJECT_DIR}/config/urls.txt" \
    "${BOOTSTRAP_NGINX_CONFIG}" \
    "${NGINX_DIR}/default.conf.tftpl"
}

create_initial_json() {
  local output_file="${PROJECT_DIR}/data/precos.json"

  if [[ ! -e "${output_file}" ]]; then
    log "Criando o arquivo JSON inicial..."

    printf '[]\n' > "${output_file}"

    chmod 0644 "${output_file}"
  fi
}

configure_basic_auth() {
  log "Configurando Basic Auth..."

  if [[ -s "${AUTH_FILE}" ]]; then
    log "O arquivo de autenticação já existe e será preservado."

    chmod 0644 "${AUTH_FILE}"

    return
  fi

  local generated_password

  generated_password="$(openssl rand -hex 24)"

  umask 077

  htpasswd \
    -bBc \
    "${AUTH_FILE}" \
    "${AUTH_USERNAME}" \
    "${generated_password}" \
    >/dev/null 2>&1

  chmod 0644 "${AUTH_FILE}"

  cat > "${INITIAL_PASSWORD_FILE}" <<EOF
Price Monitor - credenciais iniciais

Usuario: ${AUTH_USERNAME}
Senha: ${generated_password}

Para alterar a senha:

sudo htpasswd -B ${AUTH_FILE} ${AUTH_USERNAME}

Depois de validar o novo acesso, remova este arquivo:

sudo rm ${INITIAL_PASSWORD_FILE}
EOF

  chmod 0600 "${INITIAL_PASSWORD_FILE}"

  unset generated_password

  log "Credencial inicial criada."
  log "A senha inicial está em ${INITIAL_PASSWORD_FILE}."
}

activate_bootstrap_nginx_config() {
  if [[ -s "${ACTIVE_NGINX_CONFIG}" ]]; then
    log "A configuração ativa do Nginx já existe e será preservada."

    return
  fi

  log "Ativando a configuração HTTP temporária do Nginx..."

  install \
    --owner root \
    --group root \
    --mode 0644 \
    "${BOOTSTRAP_NGINX_CONFIG}" \
    "${ACTIVE_NGINX_CONFIG}"
}

validate_compose() {
  log "Validando o Docker Compose..."

  docker compose \
    --file "${COMPOSE_FILE}" \
    --profile collector \
    config \
    --quiet
}

pull_images() {
  log "Baixando as imagens Docker..."

  docker compose \
    --file "${COMPOSE_FILE}" \
    --profile collector \
    pull
}

start_application() {
  log "Iniciando o dashboard e o Nginx..."

  docker compose \
    --file "${COMPOSE_FILE}" \
    up \
    --detach \
    dashboard \
    nginx
}

show_status() {
  log "Estado atual dos containers:"

  docker compose \
    --file "${COMPOSE_FILE}" \
    ps
}

main() {
  require_root
  validate_auth_username

  configure_swap
  install_base_packages
  validate_cloud_init_packages
  install_docker

  prepare_directories
  create_initial_json
  configure_basic_auth
  activate_bootstrap_nginx_config

  validate_compose
  pull_images
  start_application
  show_status

  log "Bootstrap do Price Monitor concluído."
  log "O dashboard permanecerá bloqueado até a configuração do HTTPS."
}

main "$@"