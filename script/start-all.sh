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

source "$SCRIPT_DIR/../lib/platform.sh"
source "${LIB_DIR:-$SCRIPT_DIR/../lib}/engine.sh"
engine_load "$BASE" || exit 1
engine_require || exit 1

engine_ensure_network infra-network >/dev/null

lab_check_ssh_agent

SERVICES=(
  traefik
  wordpress-db
  mautic-db
  redis
  wordpress
  mautic
  n8n
  portainer
  adminer
  pgadmin
  mailhog
  evolution-db
  evolution-api
  web-qa
  ollama
  qdrant
  searxng
  open-webui
)

FAILED_SERVICES=()

for service in "${SERVICES[@]}"
do
  if [[ -f "$BASE/$service/EXTERNAL.txt" ]]; then
    echo "$service roda fora do Docker:"
    sed 's/^/  /' "$BASE/$service/EXTERNAL.txt"
    continue
  fi

  if [[ ! -f "$BASE/$service/docker-compose.yml" ]]; then
    echo "Ignorando $service: arquivo docker-compose.yml não encontrado em $BASE/$service"
    continue
  fi

  echo "Subindo $service"
  if ! (cd -- "$BASE/$service" && engine_compose_up_retry); then
    FAILED_SERVICES+=("$service")
  fi
done

engine ps

if ((${#FAILED_SERVICES[@]})); then
  printf 'Erro: falha ao subir os seguintes serviços: %s\n' "${FAILED_SERVICES[*]}" >&2
  exit 1
fi
