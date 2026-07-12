#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "Criando swap..."

if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile || \
    dd if=/dev/zero of=/swapfile bs=1M count=2048

  chmod 600 /swapfile
  mkswap /swapfile
fi

swapon --show | grep -q /swapfile || swapon /swapfile

grep -q '^/swapfile ' /etc/fstab || \
  echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "Instalando dependências..."

apt-get update

apt-get install -y \
  ca-certificates \
  curl \
  openssl

echo "Configurando o repositório do Docker..."

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update

apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker

usermod -aG docker ubuntu || true

echo "Criando arquivos do WordPress..."

mkdir -p /opt/wordpress/nginx
mkdir -p /opt/wordpress/secrets

if [ ! -s /opt/wordpress/secrets/db_password ]; then
  openssl rand -base64 48 \
    > /opt/wordpress/secrets/db_password
fi

if [ ! -s /opt/wordpress/secrets/db_root_password ]; then
  openssl rand -base64 48 \
    > /opt/wordpress/secrets/db_root_password
fi

chmod 0644 /opt/wordpress/secrets/db_password
chmod 0600 /opt/wordpress/secrets/db_root_password

cat > /opt/wordpress/nginx/default.conf <<'EOF'
server {
    listen 80;
    listen [::]:80;

    server_name _;
    server_tokens off;

    client_max_body_size 32m;

    location / {
        proxy_pass http://wordpress:80;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

echo "Iniciando os containers..."

cd /opt/wordpress

docker compose config
docker compose pull
docker compose up -d

echo "WordPress iniciado."