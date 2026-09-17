#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="${LAB_BASE:-$SCRIPT_DIR/../docker}"

if [[ "${1:-}" == "-b" || "${1:-}" == "--base" ]]; then
  [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
  BASE="$2"
elif [[ $# -gt 0 ]]; then
  echo "Uso: $0 [--base DIRETÓRIO]" >&2
  exit 2
fi

if ! docker info >/dev/null 2>&1; then
  echo "Erro: o Docker Engine não está acessível neste WSL." >&2
  echo "Inicie o systemd e o serviço Docker antes de continuar:" >&2
  echo "  systemctl is-system-running" >&2
  echo "  sudo systemctl start docker" >&2
  echo "Se o WSL não usar systemd, habilite [boot] systemd=true em /etc/wsl.conf e execute 'wsl --shutdown' no PowerShell." >&2
  exit 1
fi

SERVICES=(
  traefik
  wordpress-db
  mautic-db
  n8n-db
  redis
  minio
  wordpress
  mautic
  n8n
  portainer
  adminer
  pgadmin
  mailhog
  evolution-db
  evolution-api
)

for service in "${SERVICES[@]}"
do
  echo "Subindo $service"
  cd -- "$BASE/$service"
  docker compose up -d
done

docker ps
