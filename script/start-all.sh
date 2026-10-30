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

if ! docker network inspect infra-network >/dev/null 2>&1; then
  echo "Criando a rede compartilhada infra-network"
  docker network create infra-network >/dev/null
fi

if [[ -z "${SSH_AUTH_SOCK:-}" && -S "$HOME/.ssh/docker-lab-agent.sock" ]]; then
  SSH_AUTH_SOCK="$HOME/.ssh/docker-lab-agent.sock"
  export SSH_AUTH_SOCK
fi

if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
  echo "Agente SSH disponível para os containers de aplicação."
else
  echo "Aviso: agente SSH não encontrado; Git por SSH ficará indisponível nos containers." >&2
  echo "Carregue a chave com ssh-add e inicie os containers novamente." >&2
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

FAILED_SERVICES=()

for service in "${SERVICES[@]}"
do
  if [[ ! -f "$BASE/$service/docker-compose.yml" ]]; then
    echo "Ignorando $service: arquivo docker-compose.yml não encontrado em $BASE/$service"
    continue
  fi

  echo "Subindo $service"
  if ! (cd -- "$BASE/$service" && docker compose up -d --build); then
    FAILED_SERVICES+=("$service")
  fi
done

docker ps

if ((${#FAILED_SERVICES[@]})); then
  printf 'Erro: falha ao subir os seguintes serviços: %s\n' "${FAILED_SERVICES[*]}" >&2
  exit 1
fi
