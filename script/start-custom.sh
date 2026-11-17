#!/usr/bin/env bash
# Inicia somente os serviços escolhidos, com as dependências deles (por
# exemplo, wordpress também sobe wordpress-db e traefik). Lista apenas os serviços que já
# foram criados pelo create-lab.sh no diretório base.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Gerado em BASE/scripts, as bibliotecas ficam ao lado; no repositório, em lib/.
if [[ -f "$SCRIPT_DIR/services.sh" ]]; then
  LIB_DIR="$SCRIPT_DIR"
  DEFAULT_BASE="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
else
  LIB_DIR="$SCRIPT_DIR/../lib"
  DEFAULT_BASE="$HOME/docker-shared"
fi
BASE="${LAB_BASE:-$DEFAULT_BASE}"

if [[ "${1:-}" == "-b" || "${1:-}" == "--base" ]]; then
  [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
  BASE="$2"
elif [[ $# -gt 0 ]]; then
  echo "Uso: $0 [--base DIRETÓRIO]" >&2
  exit 2
fi

if [[ ! -d "$BASE" ]]; then
  echo "Erro: diretório base não encontrado: $BASE" >&2
  exit 1
fi

# shellcheck source=../lib/platform.sh
source "$LIB_DIR/platform.sh"
# shellcheck source=../lib/services.sh
source "$LIB_DIR/services.sh"
lab_require_docker || exit 1

service_exists() {
  lab_service_exists "$BASE" "$1"
}

LAB_CHOICES=()
for service in "${LAB_START_ORDER[@]}"; do
  if service_exists "$service"; then
    LAB_CHOICES+=("$service")
  fi
done

if ((${#LAB_CHOICES[@]} == 0)); then
  echo "Nenhum serviço criado em $BASE. Execute o create-lab.sh primeiro." >&2
  exit 1
fi

LAB_MENU_RUNNING="$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ' || true)"
lab_choose_services "iniciar" || exit 1

# Escolhidos + dependências, na ordem de inicialização. Dependências que não
# foram criadas são avisadas, mas não impedem as demais.
SERVICES=()
for service in "${LAB_START_ORDER[@]}"; do
  if lab_selection_requires "$service"; then
    if service_exists "$service"; then
      SERVICES+=("$service")
    else
      echo "Aviso: $service é dependência da seleção, mas não foi criado em $BASE." >&2
    fi
  fi
done

printf "\nIniciando (com dependências): %s\n\n" "${SERVICES[*]}"

if ! docker network inspect infra-network >/dev/null 2>&1; then
  echo "Criando a rede compartilhada infra-network"
  docker network create infra-network >/dev/null
fi

lab_check_ssh_agent

STATUS=0
lab_compose_up "$BASE" "${SERVICES[@]}" || STATUS=$?

docker ps --format 'table {{.Names}}\t{{.Status}}'
exit "$STATUS"
