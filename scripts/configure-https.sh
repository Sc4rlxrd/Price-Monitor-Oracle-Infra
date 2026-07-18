#!/usr/bin/env bash

set -Eeuo pipefail

readonly WORDPRESS_DIR="/opt/wordpress"
readonly NGINX_DIR="${WORDPRESS_DIR}/nginx"
readonly WEBROOT_DIR="${WORDPRESS_DIR}/certbot/www"

readonly BOOTSTRAP_CONF="${NGINX_DIR}/bootstrap.conf"
readonly HTTPS_TEMPLATE="${NGINX_DIR}/default.conf.tftpl"
readonly ACTIVE_CONF="${NGINX_DIR}/active.conf"
readonly CANDIDATE_CONF="${NGINX_DIR}/active.conf.candidate"
readonly BACKUP_CONF="${NGINX_DIR}/active.conf.before-https"

readonly PUBLIC_IP_DIR="/etc/wordpress"
readonly PUBLIC_IP_FILE="${PUBLIC_IP_DIR}/public-ip"

readonly RELOAD_SCRIPT="/usr/local/sbin/reload-wordpress-nginx.sh"
readonly DEPLOY_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
readonly DEPLOY_HOOK="${DEPLOY_HOOK_DIR}/10-reload-wordpress-nginx"

readonly NGINX_CONTAINER="wordpress-nginx"

LETSENCRYPT_EMAIL="$(
    printf '%s' "${1:-}" |
        tr --delete '\r\n'
)"

readonly LETSENCRYPT_EMAIL
readonly LETSENCRYPT_STAGING="${2:-true}"

log() {
    printf '[%s] %s\n' \
        "$(date --iso-8601=seconds)" \
        "$*"
}

fail() {
    log "ERRO: $*"
    exit 1
}

trap 'fail "Falha na linha ${LINENO}: ${BASH_COMMAND}"' ERR

if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
    fail "Informe o email do Let's Encrypt."
fi

if [[ "${EUID}" -ne 0 ]]; then
    fail "Este script precisa ser executado como root."
fi

case "${LETSENCRYPT_STAGING}" in
    true | false)
        ;;
    *)
        fail "letsencrypt_staging deve ser true ou false."
        ;;
esac

if [[ ! "${LETSENCRYPT_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
    fail "Email do Let's Encrypt inválido."
fi

for command_name in \
    curl \
    docker \
    sed \
    install \
    grep \
    sort \
    awk \
    python3
do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        fail "Comando obrigatório não encontrado: ${command_name}"
    fi
done

install \
    -d \
    -o root \
    -g root \
    -m 0755 \
    "${NGINX_DIR}" \
    "${WEBROOT_DIR}/.well-known/acme-challenge" \
    "${PUBLIC_IP_DIR}" \
    /etc/letsencrypt

if [[ ! -f "${BOOTSTRAP_CONF}" ]]; then
    fail "Arquivo não encontrado: ${BOOTSTRAP_CONF}"
fi

if [[ ! -f "${HTTPS_TEMPLATE}" ]]; then
    fail "Arquivo não encontrado: ${HTTPS_TEMPLATE}"
fi

if [[ ! -x "${RELOAD_SCRIPT}" ]]; then
    fail "Script não encontrado ou sem permissão de execução: ${RELOAD_SCRIPT}"
fi

#
# Aguarda o container Nginx iniciar.
#
log "Aguardando o container ${NGINX_CONTAINER}."

for attempt in $(seq 1 60); do
    if docker inspect \
        --format '{{.State.Running}}' \
        "${NGINX_CONTAINER}" 2>/dev/null |
        grep --quiet '^true$'
    then
        log "Container Nginx está em execução."
        break
    fi

    if [[ "${attempt}" -eq 60 ]]; then
        fail "Nginx não iniciou dentro do tempo esperado."
    fi

    sleep 5
done

#
# Testa se o webroot do desafio ACME está acessível.
#
readonly TEST_TOKEN="terraform-cloud-init-test"
readonly TEST_FILE="${WEBROOT_DIR}/.well-known/acme-challenge/${TEST_TOKEN}"

printf '%s\n' "${TEST_TOKEN}" > "${TEST_FILE}"

log "Validando o caminho HTTP do desafio ACME."

ACME_PATH_READY=false

for attempt in $(seq 1 30); do
    RESPONSE="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --max-time 5 \
            "http://127.0.0.1/.well-known/acme-challenge/${TEST_TOKEN}" ||
            true
    )"

    if [[ "${RESPONSE}" == "${TEST_TOKEN}" ]]; then
        ACME_PATH_READY=true
        break
    fi

    sleep 2
done

rm -f "${TEST_FILE}"

if [[ "${ACME_PATH_READY}" != "true" ]]; then
    fail "O Nginx não está entregando o diretório do desafio ACME."
fi

#
# Instala o Snap caso ainda não esteja disponível.
#
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

#
# Aguarda o Snap concluir sua inicialização.
#
timeout 180 snap wait system seed.loaded || true

#
# Instala o Certbot caso ainda não esteja instalado.
#
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

CERTBOT_VERSION="$(
    certbot --version |
        awk '{print $2}'
)"

readonly CERTBOT_VERSION

log "Certbot instalado: ${CERTBOT_VERSION}"

LOWEST_VERSION="$(
    printf '%s\n' \
        "5.4.0" \
        "${CERTBOT_VERSION}" |
        sort --version-sort |
        head -n 1
)"

if [[ "${LOWEST_VERSION}" != "5.4.0" ]]; then
    fail "É necessário Certbot 5.4.0 ou superior."
fi

#
# Descobre o IPv4 público usando serviços externos.
#
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

PUBLIC_IP="$(discover_public_ip)" ||
    fail "Não foi possível descobrir o IPv4 público."

readonly PUBLIC_IP

log "IPv4 público detectado: ${PUBLIC_IP}"

printf '%s\n' "${PUBLIC_IP}" > "${PUBLIC_IP_FILE}"

chown root:root "${PUBLIC_IP_FILE}"
chmod 0644 "${PUBLIC_IP_FILE}"

readonly CERTIFICATE_DIR="/etc/letsencrypt/live/${PUBLIC_IP}"
readonly FULLCHAIN_FILE="${CERTIFICATE_DIR}/fullchain.pem"
readonly PRIVATE_KEY_FILE="${CERTIFICATE_DIR}/privkey.pem"

#
# Solicita o certificado apenas se ainda não existir.
#
if [[ ! -s "${FULLCHAIN_FILE}" || ! -s "${PRIVATE_KEY_FILE}" ]]; then
    log "Solicitando certificado para ${PUBLIC_IP}."

    CERTBOT_ARGS=(
        certonly
        --non-interactive
        --agree-tos
        --email "${LETSENCRYPT_EMAIL}"
        --preferred-profile shortlived
        --webroot
        --webroot-path "${WEBROOT_DIR}"
        --ip-address "${PUBLIC_IP}"
    )

    if [[ "${LETSENCRYPT_STAGING}" == "true" ]]; then
        log "Usando ambiente staging do Let's Encrypt."

        CERTBOT_ARGS+=(--staging)
    else
        log "Usando ambiente de produção do Let's Encrypt."
    fi

    certbot "${CERTBOT_ARGS[@]}"
else
    log "Certificado já existe; emissão ignorada."
fi

if [[ ! -s "${FULLCHAIN_FILE}" ]]; then
    fail "Certificado não encontrado: ${FULLCHAIN_FILE}"
fi

if [[ ! -s "${PRIVATE_KEY_FILE}" ]]; then
    fail "Chave privada não encontrada: ${PRIVATE_KEY_FILE}"
fi

#
# Instala o hook de renovação do certificado.
#
install \
    -d \
    -o root \
    -g root \
    -m 0755 \
    "${DEPLOY_HOOK_DIR}"

install \
    -o root \
    -g root \
    -m 0755 \
    "${RELOAD_SCRIPT}" \
    "${DEPLOY_HOOK}"

#
# Renderiza a configuração HTTPS substituindo o marcador pelo IP.
#
sed \
    "s/__PUBLIC_IP__/${PUBLIC_IP}/g" \
    "${HTTPS_TEMPLATE}" \
    > "${CANDIDATE_CONF}"

chmod 0644 "${CANDIDATE_CONF}"

#
# Confirma que a configuração ativa existe antes do backup.
#
if [[ ! -f "${ACTIVE_CONF}" ]]; then
    fail "Configuração ativa do Nginx não encontrada: ${ACTIVE_CONF}"
fi

#
# Preserva a configuração HTTP para rollback.
#
cp \
    --preserve=mode,ownership \
    "${ACTIVE_CONF}" \
    "${BACKUP_CONF}"

#
# Sobrescreve o conteúdo do mesmo arquivo para preservar
# o bind mount utilizado pelo container.
#
cat "${CANDIDATE_CONF}" > "${ACTIVE_CONF}"

rm -f "${CANDIDATE_CONF}"

log "Validando configuração HTTPS do Nginx."

if ! docker exec \
    "${NGINX_CONTAINER}" \
    nginx -t
then
    log "Configuração HTTPS inválida; restaurando HTTP."

    cat "${BACKUP_CONF}" > "${ACTIVE_CONF}"

    docker exec \
        "${NGINX_CONTAINER}" \
        nginx -t

    fail "A configuração HTTPS foi rejeitada pelo Nginx."
fi

log "Recarregando o Nginx com HTTPS."

docker exec \
    "${NGINX_CONTAINER}" \
    nginx -s reload

#
# Confirma que a porta HTTPS está respondendo localmente.
# --insecure também permite testar certificados de staging.
#
HTTPS_READY=false

for attempt in $(seq 1 30); do
    if curl \
        --insecure \
        --fail \
        --silent \
        --show-error \
        --output /dev/null \
        --max-time 5 \
        "https://127.0.0.1/"
    then
        HTTPS_READY=true
        break
    fi

    sleep 2
done

if [[ "${HTTPS_READY}" != "true" ]]; then
    fail "O Nginx foi recarregado, mas o HTTPS não respondeu."
fi

log "HTTPS/TLS configurado com sucesso."
log "Acesso: https://${PUBLIC_IP}"

if [[ "${LETSENCRYPT_STAGING}" == "true" ]]; then
    log "ATENÇÃO: o certificado é de staging e não será confiável no navegador."
fi

log "Timers relacionados ao Certbot:"

systemctl list-timers \
    --all \
    --no-pager |
    grep --ignore-case certbot ||
    log "Timer do Certbot não foi localizado; verifique após o cloud-init."
