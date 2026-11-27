#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="${LAB_BASE:-$HOME/docker-shared}"
DATA="${LAB_DATA:-$HOME/lab-data}"
BACKUPS="${LAB_BACKUPS:-$HOME/backups}"
DOMAIN="${LAB_DOMAIN:-lab.test}"
OLLAMA_MODE="${LAB_OLLAMA_MODE:-auto}"
OLLAMA_URL="${LAB_OLLAMA_URL:-}"
CHECK_HARDWARE_ONLY=0
SERVICES_ARG=""
NETWORK="infra-network"
REQUESTED_ENGINE="${LAB_ENGINE:-}"
REQUESTED_HTTP_PORT=""

# shellcheck source=lib/platform.sh
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/engine.sh"
# shellcheck source=lib/hardware.sh
source "$SCRIPT_DIR/lib/hardware.sh"
# shellcheck source=lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"
ALL_SERVICES=("${LAB_ALL_SERVICES[@]}")

usage() {
  cat <<'EOF'
Uso: ./create-lab.sh [opções]

  -b, --base DIRETÓRIO   Diretório das configurações geradas (padrão: ~/docker-shared)
  -d, --data DIRETÓRIO   Diretório dos dados persistentes (padrão: ~/lab-data)
  -o, --backups DIRETÓRIO Diretório dos backups (padrão: ~/backups)
  -D, --domain DOMÍNIO   Domínio local dos serviços (padrão: lab.test)
      --engine ENGINE    docker (padrão) ou podman (Linux rootless)
      --http-port PORTA  Porta HTTP do Traefik (Docker: 80, Podman: 8000)
      --ollama-mode MODO Onde roda o Ollama: auto (padrão), native, docker,
                         docker-gpu ou remote
      --ollama-url URL   Endereço do Ollama no modo remote, por exemplo
                         http://192.168.0.20:11434
      --check-hardware   Apenas exibe o diagnóstico de hardware e sai
      --services LISTA   Serviços a criar, sem menu (ex.: "n8n qdrant" ou "IA")
  -h, --help             Exibe esta ajuda

No modo auto, o script verifica CPU, RAM, GPU e a memória do Docker e escolhe
se o Ollama roda em container ou nativo no sistema. Nos dois engines,
o modo docker do Ollama significa container com CPU.

As opções também podem ser definidas por LAB_BASE, LAB_DATA, LAB_BACKUPS,
LAB_DOMAIN, LAB_OLLAMA_MODE, LAB_OLLAMA_URL e LAB_LLM_MODEL (modelo padrão).
Os argumentos de linha de comando têm precedência sobre as variáveis.
EOF
}

while (($#)); do
  case "$1" in
    -b|--base)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    -d|--data)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
      DATA="$2"
      shift 2
      ;;
    -o|--backups)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
      BACKUPS="$2"
      shift 2
      ;;
    -D|--domain)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um domínio." >&2; exit 2; }
      DOMAIN="$2"
      shift 2
      ;;
    --engine)
      [[ $# -ge 2 ]] || { echo "Erro: --engine requer docker ou podman." >&2; exit 2; }
      engine_validate "$2" || exit 2
      REQUESTED_ENGINE="$2"
      shift 2
      ;;
    --http-port)
      [[ $# -ge 2 ]] || { echo "Erro: --http-port requer uma porta." >&2; exit 2; }
      REQUESTED_HTTP_PORT="$2"
      shift 2
      ;;
    --ollama-mode)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um modo." >&2; exit 2; }
      OLLAMA_MODE="$2"
      shift 2
      ;;
    --ollama-url)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer uma URL." >&2; exit 2; }
      OLLAMA_URL="$2"
      shift 2
      ;;
    --check-hardware)
      CHECK_HARDWARE_ONLY=1
      shift
      ;;
    --services)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer uma lista de serviços." >&2; exit 2; }
      SERVICES_ARG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Erro: opção desconhecida: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

to_platform_path() {
  local path="$1"

  if command -v wslpath >/dev/null 2>&1 && [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]; then
    wslpath -u "$path"
  elif command -v cygpath >/dev/null 2>&1 && [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]; then
    cygpath -u "$path"
  else
    printf '%s\n' "$path"
  fi
}

absolute_path() {
  local path
  path="$(to_platform_path "$1")"
  mkdir -p "$path"
  (cd -- "$path" && pwd -P)
}

BASE="$(absolute_path "$BASE")"
DATA="$(absolute_path "$DATA")"
BACKUPS="$(absolute_path "$BACKUPS")"

select_engine() {
  local compose
  engine_load "$BASE" || exit 2
  if [[ ! -f "$BASE/lab.env" ]]; then
    # Instalações anteriores a lab.env também pertencem ao Docker.
    for compose in "$BASE"/*/docker-compose.yml "$BASE"/ollama/ollama.env; do
      [[ ! -f "$compose" ]] || break
    done
    if [[ ! -f "$compose" ]]; then
      LAB_ENGINE="${REQUESTED_ENGINE:-docker}"
    fi
  fi
  engine_validate "$LAB_ENGINE" || exit 2
  if [[ -n "$REQUESTED_ENGINE" && "$REQUESTED_ENGINE" != "$LAB_ENGINE" ]]; then
    printf 'Erro: %s pertence a uma instalação %s. Use outra base e outro diretório de dados.\n' \
      "$BASE" "$LAB_ENGINE" >&2
    exit 2
  fi
}

select_engine
HTTP_PORT=""
if [[ -f "$BASE/lab.env" ]]; then
  HTTP_PORT="$(unset LAB_HTTP_PORT; source "$BASE/lab.env"; printf '%s' "${LAB_HTTP_PORT:-}")"
fi
if [[ -n "$HTTP_PORT" && -n "$REQUESTED_HTTP_PORT" && "$HTTP_PORT" != "$REQUESTED_HTTP_PORT" ]]; then
  echo "Erro: a porta HTTP já foi definida nesta instalação ($HTTP_PORT)." >&2
  exit 2
fi
HTTP_PORT="${REQUESTED_HTTP_PORT:-$HTTP_PORT}"
BIND_LABEL=""
SHARED_BIND_LABEL=""
LOCAL_IMAGE_PREFIX=""
HOST_ALIAS="host.docker.internal"
HOST_MAPPING=$'    extra_hosts:\n      - host.docker.internal:host-gateway'
TRAEFIK_SECURITY=""
N8N_USERNS=""
if [[ "$LAB_ENGINE" == podman ]]; then
  HTTP_PORT="${HTTP_PORT:-8000}"
  BIND_LABEL=":Z"
  SHARED_BIND_LABEL=",z"
  LOCAL_IMAGE_PREFIX="localhost/"
  HOST_ALIAS="host.containers.internal"
  HOST_MAPPING=""
  TRAEFIK_SECURITY=$'    security_opt:\n      - label=disable'
  N8N_USERNS='    userns_mode: "keep-id:uid=1000,gid=1000"'
  ALL_SERVICES=()
  for service in "${LAB_ALL_SERVICES[@]}"; do
    [[ "$service" == portainer ]] || ALL_SERVICES+=("$service")
  done
else
  HTTP_PORT="${HTTP_PORT:-80}"
fi
if [[ ! "$HTTP_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || ((HTTP_PORT > 65535)); then
  echo "Erro: porta HTTP inválida: $HTTP_PORT" >&2
  exit 2
fi
HTTP_SUFFIX=""
[[ "$HTTP_PORT" == 80 ]] || HTTP_SUFFIX=":$HTTP_PORT"


DOMAIN="$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  echo "Erro: domínio inválido: $DOMAIN" >&2
  exit 2
fi
if [[ "$DOMAIN" == *.local ]]; then
  echo "Aviso: no macOS, domínios .local passam pelo mDNS (Bonjour) e podem demorar segundos para resolver." >&2
fi
DOMAIN_REGEX="${DOMAIN//./\\.}"

case "$OLLAMA_MODE" in
  auto|native|docker|docker-gpu) ;;
  remote)
    if [[ ! "$OLLAMA_URL" =~ ^https?://[^[:space:]]+$ ]]; then
      echo "Erro: o modo remote requer --ollama-url http://HOST:11434" >&2
      exit 2
    fi
    OLLAMA_URL="${OLLAMA_URL%/}"
    ;;
  *)
    echo "Erro: modo do Ollama inválido: $OLLAMA_MODE (use auto, native, docker, docker-gpu ou remote)" >&2
    exit 2
    ;;
esac

services_memory_mb() {
  local total=0
  local service
  for service in "$@"; do
    total=$((total + $(lab_service_memory_mb "$service")))
  done
  echo "$total"
}

yaml_path() {
  # Aspas simples tornam seguros espaços, dois-pontos e caracteres especiais.
  printf "'%s'" "${1//\'/\'\'}"
}

if ((CHECK_HARDWARE_ONLY)); then
  lab_hw_detect "$DATA"
  lab_hw_report "$OLLAMA_MODE" "$(services_memory_mb "${ALL_SERVICES[@]}")" 1
  echo "Estimativa considerando todos os serviços do lab."
  exit 0
fi
engine_require || exit 1
if [[ "$LAB_ENGINE" == podman ]]; then
  echo "Portainer indisponível nesta configuração. Use a CLI do Podman para administração."
fi
SSH_AGENT_SOURCE="$(lab_ssh_agent_mount_source)"
SSH_AGENT_MOUNT=""
if [[ -n "$SSH_AGENT_SOURCE" ]]; then
  SSH_AGENT_MOUNT="      - $(yaml_path "$SSH_AGENT_SOURCE:/run/host-ssh-agent")"
fi

LAB_CHOICES=("${ALL_SERVICES[@]}")
if [[ -n "$SERVICES_ARG" ]]; then
  # Sem menu: só nomes e os atalhos A e IA.
  LAB_MENU=()
  _lab_parse_answer "$SERVICES_ARG" || exit 2
else
  lab_choose_services "criar" || exit 1
fi

# Verdadeiro se o serviço foi escolhido ou é dependência de um escolhido.
should_create_service() {
  lab_selection_requires "$1"
}

#############################################
# DIAGNÓSTICO DE HARDWARE
#############################################

CREATED_SERVICES=()
for service in "${ALL_SERVICES[@]}"; do
  if should_create_service "$service"; then
    CREATED_SERVICES+=("$service")
  fi
done

printf "\nSerão criados (com dependências): %s\n" "$(printf '%s\n' "${CREATED_SERVICES[@]}" | LC_ALL=C sort | tr '\n' ' ')"

WANTS_OLLAMA=0
should_create_service "ollama" && WANTS_OLLAMA=1

# Ao recriar ou adicionar serviços num lab existente, mantém o modo do Ollama
# escolhido antes (por exemplo, remote), em vez de recalcular.
if ((WANTS_OLLAMA)) && [[ "$OLLAMA_MODE" == "auto" && -f "$BASE/ollama/ollama.env" ]]; then
  PREVIOUS_OLLAMA_MODE="$(sed -n 's/^OLLAMA_MODE=//p' "$BASE/ollama/ollama.env")"
  PREVIOUS_OLLAMA_URL="$(sed -n 's/^OLLAMA_BASE_URL=//p' "$BASE/ollama/ollama.env")"
  case "$PREVIOUS_OLLAMA_MODE" in
    native|docker|docker-gpu|remote)
      OLLAMA_MODE="$PREVIOUS_OLLAMA_MODE"
      [[ "$OLLAMA_MODE" == "remote" ]] && OLLAMA_URL="$PREVIOUS_OLLAMA_URL"
      echo "Mantendo o Ollama no modo $OLLAMA_MODE já configurado (use --ollama-mode para mudar)."
      ;;
  esac
  if [[ -z "${LAB_LLM_MODEL:-}" ]]; then
    LAB_LLM_MODEL="$(sed -n 's/^LLM_MODEL=//p' "$BASE/ollama/ollama.env")"
    [[ -n "$LAB_LLM_MODEL" ]] || unset LAB_LLM_MODEL
  fi
fi

lab_hw_detect "$DATA"
lab_hw_report "$OLLAMA_MODE" "$(services_memory_mb "${CREATED_SERVICES[@]}")" "$WANTS_OLLAMA"

if ((WANTS_OLLAMA)); then
  if [[ "$LAB_ENGINE" == podman && "$HW_OLLAMA_MODE" == docker-gpu ]]; then
    echo "Erro: o modo de GPU em container está disponível apenas com Docker. Use native, remote ou docker com Podman." >&2
    exit 2
  fi
  OLLAMA_MODE="$HW_OLLAMA_MODE"
  LLM_MODEL="$HW_LLM_MODEL"
  if [[ "$OLLAMA_MODE" == "docker-gpu" ]] && ((!HW_DOCKER_GPU)); then
    echo "Alerta: --ollama-mode docker-gpu escolhido, mas o Docker não tem acesso a uma GPU NVIDIA." >&2
    HW_WARNINGS=$((HW_WARNINGS + 1))
  fi
  case "$OLLAMA_MODE" in
    docker|docker-gpu) OLLAMA_URL="http://ollama:11434" ;;
    native) OLLAMA_URL="http://$HOST_ALIAS:11434" ;;
  esac
fi

if ((HW_WARNINGS)); then
  read -r -p "Há $HW_WARNINGS alerta(s) acima. Continuar mesmo assim? [s/N] " confirm || confirm=""
  case "$confirm" in
    s|S|sim|SIM|y|Y) ;;
    *) echo "Cancelado."; exit 1 ;;
  esac
fi

if should_create_service traefik && [[ "$LAB_ENGINE" == podman ]]; then
  read -r port_floor < /proc/sys/net/ipv4/ip_unprivileged_port_start
  if ((HTTP_PORT < port_floor)); then
    printf 'Erro: a porta %s requer privilégios. Use --http-port com valor a partir de %s.\n' "$HTTP_PORT" "$port_floor" >&2
    exit 1
  fi
  engine_require_socket || exit 1
fi

INSTALL_LOCK="$BASE/.lab-install-lock"
if ! mkdir -- "$INSTALL_LOCK"; then
  echo "Erro: já existe uma instalação em andamento em $BASE." >&2
  exit 1
fi
trap 'rm -f -- "$INSTALL_LOCK/lab.env"; rmdir -- "$INSTALL_LOCK"' EXIT
# Confira a escolha de novo após adquirir a trava da instalação.
# A seleção explícita impede que uma instalação criada durante o menu seja adotada.
REQUESTED_ENGINE="$LAB_ENGINE"
select_engine
if [[ -f "$BASE/lab.env" ]]; then
  SAVED_HTTP_PORT="$(unset LAB_HTTP_PORT; source "$BASE/lab.env"; printf '%s' "${LAB_HTTP_PORT:-80}")"
  if [[ "$HTTP_PORT" != "$SAVED_HTTP_PORT" ]]; then
    echo "Erro: a instalação já está configurada para a porta $SAVED_HTTP_PORT." >&2
    exit 2
  fi
fi

DATA_ENGINE_FILE="$DATA/.lab-engine"
if [[ ! -f "$DATA_ENGINE_FILE" ]]; then
  if [[ "$LAB_ENGINE" == podman && -n "$(find "$DATA" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Erro: use um diretório de dados vazio para uma nova instalação Podman." >&2
    exit 2
  fi
  (set -o noclobber; printf '%s\n' "$LAB_ENGINE" > "$DATA_ENGINE_FILE") 2>/dev/null || true
fi
if ! read -r DATA_ENGINE < "$DATA_ENGINE_FILE" || [[ "$DATA_ENGINE" != "$LAB_ENGINE" ]]; then
  printf 'Erro: %s não está associado ao engine %s. Use outro diretório de dados.\n' "$DATA" "$LAB_ENGINE" >&2
  exit 2
fi

mkdir -p "$BASE/scripts" "$BASE/networks" "$BASE/certificates" "$BASE/templates"
cp -- "$SCRIPT_DIR/lib/"{platform,engine,services}.sh "$BASE/scripts/"
for helper in start-custom.sh update-lab.sh; do
  cp -- "$SCRIPT_DIR/script/$helper" "$BASE/scripts/$helper"
  chmod +x "$BASE/scripts/$helper"
done

# Caminhos usados pelos scripts gerados (update-lab.sh precisa deles para
# backups e para chamar este instalador ao adicionar serviços).
cat > "$INSTALL_LOCK/lab.env" <<EOF_LAB_ENV
# Gerado por create-lab.sh.
LAB_ENGINE=$LAB_ENGINE
LAB_HTTP_PORT=$HTTP_PORT
LAB_DATA=$(printf '%q' "$DATA")
LAB_BACKUPS=$(printf '%q' "$BACKUPS")
LAB_DOMAIN=$(printf '%q' "$DOMAIN")
LAB_REPO=$(printf '%q' "$SCRIPT_DIR")
EOF_LAB_ENV
mv -f -- "$INSTALL_LOCK/lab.env" "$BASE/lab.env"
mkdir -p "$BACKUPS/databases" "$BACKUPS/volumes" "$BACKUPS/projects"

if should_create_service "traefik"; then
  mkdir -p "$BASE/traefik"
fi

if should_create_service "wordpress" || should_create_service "wordpress-db"; then
  mkdir -p "$BASE/wordpress" "$BASE/wordpress-db" "$DATA/wordpress/files" "$DATA/wordpress/secrets"

  WORDPRESS_DB_PASSWORD_FILE="$DATA/wordpress/secrets/db_password"
  if [[ ! -f "$WORDPRESS_DB_PASSWORD_FILE" ]]; then
    printf '%s' 'wordpress123' > "$WORDPRESS_DB_PASSWORD_FILE"
    chmod 600 "$WORDPRESS_DB_PASSWORD_FILE" 2>/dev/null || true
  fi
  if [[ "$LAB_ENGINE" == podman ]]; then
    # O PHP lê o arquivo como www-data no container. O diretório no host
    # restringe o acesso ao usuário que instalou o Lab.
    chmod 700 "$DATA/wordpress/secrets"
    chmod 644 "$WORDPRESS_DB_PASSWORD_FILE"
  fi
fi

if should_create_service "mautic" || should_create_service "mautic-db"; then
  mkdir -p "$BASE/mautic" "$BASE/mautic-db"
fi

if should_create_service "n8n"; then
  mkdir -p "$BASE/n8n" "$DATA/n8n/data" "$DATA/n8n/arquivos"
fi

if should_create_service "redis"; then
  mkdir -p "$BASE/redis"
fi

if should_create_service "minio"; then
  mkdir -p "$BASE/minio"
fi

if should_create_service "portainer"; then
  mkdir -p "$BASE/portainer"
fi

if should_create_service "adminer"; then
  mkdir -p "$BASE/adminer"
fi

if should_create_service "pgadmin"; then
  mkdir -p "$BASE/pgadmin"
fi

if should_create_service "mailhog"; then
  mkdir -p "$BASE/mailhog"
fi

if should_create_service "evolution-api" || should_create_service "evolution-db"; then
  mkdir -p "$BASE/evolution-api" "$BASE/evolution-db"
fi

mkdir -p "$DATA"

if should_create_service "redis"; then
  mkdir -p "$DATA/redis"
fi

if should_create_service "minio"; then
  mkdir -p "$DATA/minio"
fi

if should_create_service "portainer"; then
  mkdir -p "$DATA/portainer"
fi

if should_create_service "pgadmin"; then
  mkdir -p "$DATA/pgadmin"
fi

if should_create_service "evolution-api"; then
  mkdir -p "$DATA/evolution-api"
fi

if should_create_service "ollama"; then
  mkdir -p "$BASE/ollama"
  if [[ "$OLLAMA_MODE" == docker* ]]; then
    mkdir -p "$DATA/ollama"
  fi
fi

if should_create_service "qdrant"; then
  mkdir -p "$BASE/qdrant" "$DATA/qdrant"
fi

if should_create_service "open-webui"; then
  mkdir -p "$BASE/open-webui" "$DATA/open-webui"
fi

if should_create_service "searxng"; then
  mkdir -p "$BASE/searxng/config"
fi

engine_ensure_network "$NETWORK"

#############################################
# TRAEFIK
#############################################

if should_create_service "traefik"; then
cat > "$BASE/traefik/docker-compose.yml" <<EOF_TRAEFIK
services:
  traefik:
    image: docker.io/library/traefik:v3
    container_name: traefik
    restart: unless-stopped

    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=$NETWORK
      - --entrypoints.web.address=:80
      - --api.dashboard=true
      - --api.insecure=true

    ports:
      - "$HTTP_PORT:80"
      - "8088:8080"

    volumes:
      - $(yaml_path "$(engine_socket):/var/run/docker.sock:ro")
$TRAEFIK_SECURITY

    labels:
      - traefik.enable=true
      - traefik.http.routers.traefik.rule=Host(\`traefik.${DOMAIN}\`)
      - traefik.http.routers.traefik.entrypoints=web
      - traefik.http.routers.traefik.service=api@internal
      - traefik.http.routers.traefik.middlewares=dashboard
      - traefik.http.middlewares.dashboard.redirectregex.regex=^http://traefik\\.${DOMAIN_REGEX}${HTTP_SUFFIX}/?\$
      - traefik.http.middlewares.dashboard.redirectregex.replacement=http://traefik.${DOMAIN}${HTTP_SUFFIX}/dashboard/

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_TRAEFIK
fi

#############################################
# WORDPRESS DB
#############################################

if should_create_service "wordpress-db"; then
cat > "$BASE/wordpress-db/docker-compose.yml" <<EOF_WORDPRESS_DB
services:
  wordpress-db:
    image: docker.io/library/mysql:8
    container_name: wordpress-db

    restart: unless-stopped

    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD_FILE: /run/secrets/wordpress_db_password

    volumes:
      - wordpress-db-data:/var/lib/mysql
      - $(yaml_path "$DATA/wordpress/secrets/db_password:/run/secrets/wordpress_db_password:ro${SHARED_BIND_LABEL}")

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  wordpress-db-data:
    name: wordpress-db-data
EOF_WORDPRESS_DB
fi

#############################################
# WORDPRESS
#############################################

if should_create_service "wordpress"; then
cat > "$BASE/wordpress/Dockerfile" <<'EOF_WORDPRESS_DOCKERFILE'
FROM docker.io/library/wordpress:latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp
EOF_WORDPRESS_DOCKERFILE

cat > "$BASE/wordpress/docker-compose.yml" <<EOF_WORDPRESS
services:
  wordpress:
    image: ${LOCAL_IMAGE_PREFIX}wordpress-lab:latest
    build:
      context: .
      dockerfile: Dockerfile

    container_name: wordpress

    restart: unless-stopped

    environment:
      SSH_AUTH_SOCK: /run/host-ssh-agent
      WORDPRESS_DB_HOST: wordpress-db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD_FILE: /run/secrets/wordpress_db_password
      WORDPRESS_ENVIRONMENT_TYPE: local

    volumes:
$SSH_AGENT_MOUNT
      - $(yaml_path "$DATA/wordpress/files:/var/www/html/${BIND_LABEL}")
      - $(yaml_path "$DATA/wordpress/secrets/db_password:/run/secrets/wordpress_db_password:ro${SHARED_BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.wordpress.rule=Host(\`wordpress.${DOMAIN}\`)
      - traefik.http.services.wordpress.loadbalancer.server.port=80

    networks:
      infra:
        aliases:
          - wordpress.${DOMAIN}

networks:
  infra:
    external: true
    name: infra-network
EOF_WORDPRESS
fi

#############################################
# MAUTIC DB
#############################################

if should_create_service "mautic-db"; then
cat > "$BASE/mautic-db/docker-compose.yml" <<EOF_MAUTIC_DB
services:
  mautic-db:
    image: docker.io/library/mariadb:11

    container_name: mautic-db

    restart: unless-stopped

    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: mautic
      MYSQL_USER: mautic
      MYSQL_PASSWORD: mautic123

    volumes:
      - mautic-db-data:/var/lib/mysql

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  mautic-db-data:
    name: mautic-db-data
EOF_MAUTIC_DB
fi

#############################################
# MAUTIC
#############################################

if should_create_service "mautic"; then
cat > "$BASE/mautic/Dockerfile" <<'EOF_MAUTIC_DOCKERFILE'
FROM docker.io/mautic/mautic:7.1.2-apache

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/*
EOF_MAUTIC_DOCKERFILE

cat > "$BASE/mautic/docker-compose.yml" <<EOF_MAUTIC
services:
  mautic:
    image: ${LOCAL_IMAGE_PREFIX}mautic-lab:latest
    build:
      context: .
      dockerfile: Dockerfile

    container_name: mautic

    restart: unless-stopped

    environment:
      SSH_AUTH_SOCK: /run/host-ssh-agent
      MAUTIC_DB_HOST: mautic-db
      MAUTIC_DB_PORT: "3306"
      MAUTIC_DB_USER: mautic
      MAUTIC_DB_PASSWORD: mautic123
      MAUTIC_DB_DATABASE: mautic

    volumes:
$SSH_AGENT_MOUNT
      - mautic-config-data:/var/www/html/config
      - mautic-media-files-data:/var/www/html/docroot/media/files
      - mautic-media-images-data:/var/www/html/docroot/media/images
      - mautic-logs-data:/var/www/html/var/logs

    labels:
      - traefik.enable=true
      - traefik.http.routers.mautic.rule=Host(\`mautic.${DOMAIN}\`)
      - traefik.http.services.mautic.loadbalancer.server.port=80

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  mautic-config-data:
    name: mautic-config-data
  mautic-media-files-data:
    name: mautic-media-files-data
  mautic-media-images-data:
    name: mautic-media-images-data
  mautic-logs-data:
    name: mautic-logs-data
EOF_MAUTIC
fi

#############################################
# N8N
#############################################

if should_create_service "n8n"; then
cat > "$BASE/n8n/docker-compose.yml" <<EOF_N8N
services:
  n8n:
    image: docker.io/n8nio/n8n:latest

    container_name: n8n

    restart: unless-stopped

    environment:
      SSH_AUTH_SOCK: /run/host-ssh-agent
      N8N_HOST: n8n.${DOMAIN}
      N8N_PROTOCOL: http
      N8N_SECURE_COOKIE: "false"
      WEBHOOK_URL: http://n8n.${DOMAIN}${HTTP_SUFFIX}/
      N8N_RESTRICT_FILE_ACCESS_TO: /data/arquivos

$HOST_MAPPING
$N8N_USERNS

    volumes:
$SSH_AGENT_MOUNT
      - $(yaml_path "$DATA/n8n/data:/home/node/${BIND_LABEL}")
      - $(yaml_path "$DATA/n8n/arquivos:/data/arquivos${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(\`n8n.${DOMAIN}\`)
      - traefik.http.services.n8n.loadbalancer.server.port=5678

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_N8N

  cat > "$BASE/n8n/update.sh" <<'EOF_N8N_UPDATE'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd -- "$SCRIPT_DIR"

source "$SCRIPT_DIR/../scripts/platform.sh"
source "$SCRIPT_DIR/../scripts/engine.sh"
engine_load "$SCRIPT_DIR/.." || exit 1
engine_require || exit 1
lab_check_ssh_agent "no n8n"

echo "Baixando a imagem atual do n8n..."
if ! engine_compose pull; then
  echo "Erro: a imagem não foi baixada; o container não será recriado." >&2
  echo "Verifique a conectividade IPv4/DNS do engine e tente novamente." >&2
  exit 1
fi

echo "Recriando o container n8n..."
engine_compose up -d --force-recreate
engine_exec n8n n8n --version
EOF_N8N_UPDATE
  chmod +x "$BASE/n8n/update.sh"
fi

#############################################
# REDIS
#############################################

if should_create_service "redis"; then
cat > "$BASE/redis/docker-compose.yml" <<EOF_REDIS
services:
  redis:
    image: docker.io/library/redis:latest

    container_name: redis

    restart: unless-stopped

    volumes:
      - $(yaml_path "$DATA/redis:/data${BIND_LABEL}")

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_REDIS
fi

#############################################
# MINIO
#############################################

if should_create_service "minio"; then
cat > "$BASE/minio/docker-compose.yml" <<EOF_MINIO
services:
  minio:
    image: docker.io/minio/minio

    container_name: minio

    command: server /data --console-address ":9001"

    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: admin123

    volumes:
      - $(yaml_path "$DATA/minio:/data${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.minio.rule=Host(\`minio.${DOMAIN}\`)
      - traefik.http.services.minio.loadbalancer.server.port=9001

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  minio-data:
EOF_MINIO
fi

#############################################
# PORTAINER
#############################################

if should_create_service "portainer"; then
cat > "$BASE/portainer/docker-compose.yml" <<EOF_PORTAINER
services:
  portainer:
    image: docker.io/portainer/portainer-ce:latest

    container_name: portainer

    restart: unless-stopped

    volumes:
      - $(yaml_path "$(engine_socket):/var/run/docker.sock")
      - $(yaml_path "$DATA/portainer:/data${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=Host(\`portainer.${DOMAIN}\`)
      - traefik.http.services.portainer.loadbalancer.server.port=9000

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  portainer-data:
EOF_PORTAINER
fi

#############################################
# MAILHOG
#############################################

if should_create_service "mailhog"; then
cat > "$BASE/mailhog/docker-compose.yml" <<EOF_MAILHOG
services:
  mailhog:
    # Mailpit substitui o MailHog (abandonado e sem imagem arm64) mantendo o
    # nome mailhog e as portas, para não quebrar o SMTP já configurado nas apps.
    image: docker.io/axllent/mailpit:latest

    container_name: mailhog

    restart: unless-stopped

    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: "1"
      MP_SMTP_AUTH_ALLOW_INSECURE: "1"

    ports:
      - "8026:8025"
      - "1026:1025"

    labels:
      - traefik.enable=true
      - traefik.http.routers.mailhog.rule=Host(\`mailhog.${DOMAIN}\`)
      - traefik.http.services.mailhog.loadbalancer.server.port=8025

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_MAILHOG
fi

#############################################
# ADMINER
#############################################

if should_create_service "adminer"; then
cat > "$BASE/adminer/docker-compose.yml" <<EOF_ADMINER
services:
  adminer:
    image: docker.io/library/adminer

    container_name: adminer

    restart: unless-stopped

    labels:
      - traefik.enable=true
      - traefik.http.routers.adminer.rule=Host(\`adminer.${DOMAIN}\`)
      - traefik.http.services.adminer.loadbalancer.server.port=8080

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_ADMINER
fi

#############################################
# PGADMIN
#############################################

if should_create_service "pgadmin"; then
cat > "$BASE/pgadmin/docker-compose.yml" <<EOF_PGADMIN
services:
  pgadmin:
    image: docker.io/dpage/pgadmin4

    container_name: pgadmin

    restart: unless-stopped

    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: admin123

    volumes:
      - pgadmin-data:/var/lib/pgadmin

    labels:
      - traefik.enable=true
      - traefik.http.routers.pgadmin.rule=Host(\`pgadmin.${DOMAIN}\`)
      - traefik.http.services.pgadmin.loadbalancer.server.port=80

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  pgadmin-data:
    name: pgadmin-data
EOF_PGADMIN
fi

#############################################
# EVOLUTION DB
#############################################

if should_create_service "evolution-db"; then
cat > "$BASE/evolution-db/docker-compose.yml" <<EOF_EVOLUTION_DB
services:
  evolution-db:
    image: docker.io/library/postgres:16-alpine
    container_name: evolution-db
    restart: unless-stopped

    environment:
      POSTGRES_DB: evolution
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres123

    volumes:
      - evolution-db-data:/var/lib/postgresql/data

    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d evolution"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 10s

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  evolution-db-data:
    name: evolution-db-data
EOF_EVOLUTION_DB
fi

#############################################
# EVOLUTION API
#############################################

if should_create_service "evolution-api"; then
cat > "$BASE/evolution-api/Dockerfile" <<'EOF_EVOLUTION_DOCKERFILE'
FROM docker.io/evoapicloud/evolution-api:v2.3.7

USER root
RUN apk add --no-cache git openssh-client
EOF_EVOLUTION_DOCKERFILE

cat > "$BASE/evolution-api/docker-compose.yml" <<EOF_EVOLUTION_API
services:
  evolution-api:
    image: ${LOCAL_IMAGE_PREFIX}evolution-api-lab:latest
    build:
      context: .
      dockerfile: Dockerfile

    container_name: evolution-api
    restart: unless-stopped

    ports:
      - "8080:8080"

    environment:
      SSH_AUTH_SOCK: /run/host-ssh-agent
      AUTHENTICATION_API_KEY: change-me
      SERVER_URL: http://evolution-api.${DOMAIN}${HTTP_SUFFIX}
      SERVER_DISABLE_MANAGER: "false"
      NODE_OPTIONS: --dns-result-order=ipv4first
      DATABASE_ENABLED: "true"
      DATABASE_PROVIDER: postgresql
      DATABASE_CONNECTION_URI: postgresql://postgres:postgres123@evolution-db:5432/evolution
      DATABASE_CONNECTION_CLIENT_NAME: evolution_api
      DATABASE_SAVE_DATA_INSTANCE: "true"
      DATABASE_SAVE_DATA_NEW_MESSAGE: "true"
      DATABASE_SAVE_MESSAGE_UPDATE: "true"
      DATABASE_SAVE_DATA_CONTACTS: "true"
      DATABASE_SAVE_DATA_CHATS: "true"
      DATABASE_SAVE_DATA_LABELS: "true"
      DATABASE_SAVE_DATA_HISTORIC: "true"
      CACHE_REDIS_ENABLED: "true"
      CACHE_REDIS_URI: redis://redis:6379/1
      CACHE_REDIS_PREFIX_KEY: evolution_api
      CACHE_REDIS_SAVE_INSTANCES: "false"
      CACHE_LOCAL_ENABLED: "false"
      S3_ENABLED: "false"

    volumes:
$SSH_AGENT_MOUNT
      - $(yaml_path "$DATA/evolution-api:/evolution/instances${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.evolution-api.rule=Host(\`evolution-api.${DOMAIN}\`)
      - traefik.http.routers.evolution-api.entrypoints=web
      - traefik.http.routers.evolution-api.service=evolution-api
      - traefik.http.services.evolution-api.loadbalancer.server.port=8080

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_EVOLUTION_API
fi

#############################################
# OLLAMA
#############################################

if should_create_service "ollama"; then
  # Remove o que sobrou de um modo anterior antes de gerar o atual.
  rm -f -- "$BASE/ollama/docker-compose.yml" "$BASE/ollama/EXTERNAL.txt"

  case "$OLLAMA_MODE" in
    docker|docker-gpu)
      OLLAMA_GPU_BLOCK=""
      if [[ "$OLLAMA_MODE" == "docker-gpu" ]]; then
        OLLAMA_GPU_BLOCK="
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
"
      fi
cat > "$BASE/ollama/docker-compose.yml" <<EOF_OLLAMA
services:
  ollama:
    image: docker.io/ollama/ollama:latest

    container_name: ollama

    restart: unless-stopped

    # Sem Traefik nem porta publicada: só os containers da infra-network
    # acessam a API, em http://ollama:11434.
    environment:
      OLLAMA_KEEP_ALIVE: 10m
      # Modelo de chat + modelo de embedding carregados ao mesmo tempo.
      OLLAMA_MAX_LOADED_MODELS: "2"
      OLLAMA_NUM_PARALLEL: "1"

    volumes:
      - $(yaml_path "$DATA/ollama:/root/.ollama${BIND_LABEL}")
${OLLAMA_GPU_BLOCK}
    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_OLLAMA
      ;;
    native)
      {
        echo "Ollama nativo, acessado pelos containers em $OLLAMA_URL."
        case "$(lab_platform)" in
          macos)
            echo "Instale com 'brew install ollama' e inicie com 'brew services start ollama'"
            echo "(ou use o app de https://ollama.com/download)."
            ;;
          wsl)
            if ((HW_DOCKER_DESKTOP)); then
              echo "Instale o Ollama para Windows (https://ollama.com/download); o Docker Desktop"
              echo "alcança o Windows por host.docker.internal."
            else
              echo "Instale no WSL: curl -fsSL https://ollama.com/install.sh | sh"
              echo "Depois libere o acesso dos containers: sudo systemctl edit ollama"
              echo "  [Service]"
              echo "  Environment=\"OLLAMA_HOST=0.0.0.0:11434\""
              echo "e reinicie: sudo systemctl restart ollama"
            fi
            ;;
          gitbash)
            echo "Instale o Ollama para Windows (https://ollama.com/download)."
            ;;
          *)
            echo "Instale com: curl -fsSL https://ollama.com/install.sh | sh"
            echo "Libere o acesso dos containers com OLLAMA_HOST=0.0.0.0:11434 (sudo systemctl edit ollama)"
            echo "e bloqueie a porta 11434 no firewall para a rede externa."
            ;;
        esac
        echo "Baixe os modelos com: $BASE/ollama/pull-models.sh"
      } > "$BASE/ollama/EXTERNAL.txt"
      ;;
    remote)
      {
        echo "Ollama remoto em $OLLAMA_URL."
        echo "Na outra máquina, o Ollama precisa escutar na rede (OLLAMA_HOST=0.0.0.0:11434)"
        echo "e a porta 11434 deve estar liberada só para a rede local."
      } > "$BASE/ollama/EXTERNAL.txt"
      ;;
  esac

  cat > "$BASE/ollama/ollama.env" <<EOF_OLLAMA_ENV
# Gerado por create-lab.sh. Use OLLAMA_BASE_URL nas credenciais do n8n,
# no Open WebUI e em outros containers da infra-network.
OLLAMA_MODE=$OLLAMA_MODE
OLLAMA_BASE_URL=$OLLAMA_URL
LLM_MODEL=$LLM_MODEL
EMBED_MODEL=nomic-embed-text
EOF_OLLAMA_ENV

  cat > "$BASE/ollama/pull-models.sh" <<'EOF_OLLAMA_PULL'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama.env"
source "$SCRIPT_DIR/../scripts/engine.sh"
engine_load "$SCRIPT_DIR/.." || exit 1

if (($#)); then
  MODELS=("$@")
else
  MODELS=("$LLM_MODEL" "$EMBED_MODEL")
fi

pull() {
  local model="$1"
  local api_url

  echo "Baixando $model ($OLLAMA_MODE)..."
  case "$OLLAMA_MODE" in
    docker|docker-gpu)
      engine_exec ollama ollama pull "$model"
      return
      ;;
    native)
      if command -v ollama >/dev/null 2>&1; then
        ollama pull "$model"
        return
      fi
      if command -v ollama.exe >/dev/null 2>&1; then
        ollama.exe pull "$model"
        return
      fi
      api_url="http://localhost:11434"
      ;;
    remote)
      api_url="$OLLAMA_BASE_URL"
      ;;
  esac

  curl -fsS -X POST "$api_url/api/pull" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$model\",\"stream\":false}"
  echo
}

for model in "${MODELS[@]}"; do
  pull "$model"
done
EOF_OLLAMA_PULL
  chmod +x "$BASE/ollama/pull-models.sh"
fi

#############################################
# QDRANT
#############################################

if should_create_service "qdrant"; then
cat > "$BASE/qdrant/docker-compose.yml" <<EOF_QDRANT
services:
  qdrant:
    image: docker.io/qdrant/qdrant:latest

    container_name: qdrant

    restart: unless-stopped

    # API REST em http://qdrant:6333 dentro da rede; painel em
    # http://qdrant.${DOMAIN}${HTTP_SUFFIX}/dashboard
    volumes:
      - $(yaml_path "$DATA/qdrant:/qdrant/storage${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.qdrant.rule=Host(\`qdrant.${DOMAIN}\`)
      - traefik.http.routers.qdrant.entrypoints=web
      - traefik.http.services.qdrant.loadbalancer.server.port=6333

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_QDRANT
fi

#############################################
# OPEN WEBUI
#############################################

if should_create_service "open-webui"; then
cat > "$BASE/open-webui/docker-compose.yml" <<EOF_OPEN_WEBUI
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main

    container_name: open-webui

    restart: unless-stopped

    # O primeiro usuário cadastrado vira administrador.
    environment:
      OLLAMA_BASE_URL: ${OLLAMA_URL}

$HOST_MAPPING

    volumes:
      - $(yaml_path "$DATA/open-webui:/app/backend/data${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.open-webui.rule=Host(\`open-webui.${DOMAIN}\`)
      - traefik.http.routers.open-webui.entrypoints=web
      - traefik.http.services.open-webui.loadbalancer.server.port=8080

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_OPEN_WEBUI
fi

#############################################
# SEARXNG
#############################################

if should_create_service "searxng"; then
  # Mantém o settings.yml existente para não trocar a chave nem perder ajustes.
  if [[ ! -f "$BASE/searxng/config/settings.yml" ]]; then
    SEARXNG_SECRET="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
    cat > "$BASE/searxng/config/settings.yml" <<EOF_SEARXNG_SETTINGS
use_default_settings: true

server:
  secret_key: "${SEARXNG_SECRET}"
  limiter: false
  image_proxy: false

search:
  # json é o formato usado pelos agentes (n8n: http://searxng:8080/search?q=...&format=json)
  formats:
    - html
    - json
EOF_SEARXNG_SETTINGS
  fi

cat > "$BASE/searxng/docker-compose.yml" <<EOF_SEARXNG
services:
  searxng:
    image: docker.io/searxng/searxng:latest

    container_name: searxng

    restart: unless-stopped

    environment:
      SEARXNG_BASE_URL: http://searxng.${DOMAIN}${HTTP_SUFFIX}/

    volumes:
      - $(yaml_path "$BASE/searxng/config:/etc/searxng${BIND_LABEL}")

    labels:
      - traefik.enable=true
      - traefik.http.routers.searxng.rule=Host(\`searxng.${DOMAIN}\`)
      - traefik.http.routers.searxng.entrypoints=web
      - traefik.http.services.searxng.loadbalancer.server.port=8080

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_SEARXNG
fi

#############################################
# WEB-QA
#############################################

if should_create_service "web-qa"; then
  mkdir -p "$BASE/web-qa"
  (umask 077; mkdir -p "$DATA/web-qa/artifacts")
  cp -- "$SCRIPT_DIR/web-qa/"{Dockerfile,package.json,package-lock.json} "$BASE/web-qa/"
  cp -R -- "$SCRIPT_DIR/web-qa/examples" "$BASE/web-qa/"
  QA_USER="$(id -u):$(id -g)"
  QA_USERNS=""
  if [[ "$LAB_ENGINE" == podman ]]; then
    QA_USER="1000:1000"
    QA_USERNS="$N8N_USERNS"
  fi
  while IFS= read -r line; do
    case "$line" in
      *'@IMAGE_PREFIX@'*) line="${line//@IMAGE_PREFIX@/$LOCAL_IMAGE_PREFIX}" ;;
      *'@USER@'*) line="${line//@USER@/$QA_USER}" ;;
      *'@USERNS@'*) [[ -n "$QA_USERNS" ]] || continue; line="$QA_USERNS" ;;
      *'@DOMAIN@'*) line="${line//@DOMAIN@/$DOMAIN}" ;;
      *'@HTTP_PORT@'*) line="${line//@HTTP_PORT@/$HTTP_PORT}" ;;
      *'@ARTIFACTS_MOUNT@'*) line="      - $(yaml_path "$DATA/web-qa/artifacts:/artifacts${BIND_LABEL}")" ;;
    esac
    printf '%s\n' "$line"
  done < "$SCRIPT_DIR/web-qa/docker-compose.yml.in" > "$BASE/web-qa/docker-compose.yml"
fi

#############################################
# START-ALL
#############################################

START_SERVICES=("${LAB_START_ORDER[@]}")

cat > "$BASE/scripts/start-all.sh" <<'EOF_START'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="${LAB_BASE:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"

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

source "$SCRIPT_DIR/platform.sh"
source "$SCRIPT_DIR/engine.sh"
engine_load "$BASE" || exit 1
engine_require || exit 1

engine_ensure_network infra-network >/dev/null

lab_check_ssh_agent

SERVICES=(
EOF_START
for service in "${START_SERVICES[@]}"; do
  printf '  %s\n' "$service" >> "$BASE/scripts/start-all.sh"
done
cat >> "$BASE/scripts/start-all.sh" <<'EOF_START_END'
)

FAILED_SERVICES=()

for service in "${SERVICES[@]}"
do
  # Serviços que rodam fora do Docker (Ollama nativo ou remoto) deixam um
  # aviso com instruções no lugar do docker-compose.yml.
  if [[ -f "$BASE/$service/EXTERNAL.txt" ]]; then
    echo "$service roda fora do engine:"
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
EOF_START_END

chmod +x "$BASE/scripts/start-all.sh"

#############################################
# STOP-ALL
#############################################

STOP_SERVICES=()
for ((index=${#START_SERVICES[@]}-1; index>=0; index--)); do
  STOP_SERVICES+=("${START_SERVICES[index]}")
done

cat > "$BASE/scripts/stop-all.sh" <<'EOF_STOP'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="${LAB_BASE:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"

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

source "$SCRIPT_DIR/platform.sh"
source "$SCRIPT_DIR/engine.sh"
engine_load "$BASE" || exit 1
engine_require || exit 1

SERVICES=(
EOF_STOP
for service in "${STOP_SERVICES[@]}"; do
  printf '  %s\n' "$service" >> "$BASE/scripts/stop-all.sh"
done
cat >> "$BASE/scripts/stop-all.sh" <<'EOF_STOP_END'
)

FAILED_SERVICES=()

for service in "${SERVICES[@]}"
do
  if [[ ! -f "$BASE/$service/docker-compose.yml" ]]; then
    echo "Ignorando $service: arquivo docker-compose.yml não encontrado em $BASE/$service"
    continue
  fi

  echo "Parando $service"
  if ! (cd -- "$BASE/$service" && engine_compose down); then
    FAILED_SERVICES+=("$service")
  fi
done

if ((${#FAILED_SERVICES[@]})); then
  printf 'Erro: falha ao parar os seguintes serviços: %s\n' "${FAILED_SERVICES[*]}" >&2
  exit 1
fi
EOF_STOP_END

chmod +x "$BASE/scripts/stop-all.sh"

#############################################
# HOSTS
#############################################

# Inclui todos os serviços existentes, não só os desta execução.
lab_write_hosts "$BASE" "$DOMAIN"

cat > "$BASE/scripts/update-hosts.sh" <<'EOF_HOSTS_UPDATE'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
HOSTS_FILE="$BASE/hosts-lab.txt"
MODE="both"

source "$SCRIPT_DIR/platform.sh"
PLATFORM="$(lab_platform)"
TEMP_FILE=""

cleanup() {
  if [[ -n "$TEMP_FILE" ]]; then
    rm -f -- "$TEMP_FILE"
    TEMP_FILE=""
  fi
}
trap cleanup EXIT

usage() {
  echo "Uso: $0 [--local-only | --windows-only]"
  echo "  --local-only    atualiza somente /etc/hosts (macOS, Linux ou WSL); --wsl-only é aceito como alias"
  echo "  --windows-only  atualiza somente o hosts do Windows (a partir do WSL)"
}

while (($#)); do
  case "$1" in
    --local-only|--wsl-only) MODE="local"; shift ;;
    --windows-only) MODE="windows"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Erro: opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -s "$HOSTS_FILE" ]]; then
  echo "Erro: arquivo de hosts ausente ou vazio: $HOSTS_FILE" >&2
  exit 1
fi

update_local_hosts() {
  TEMP_FILE="$(mktemp)"

  if ! awk '
    $0 == "# BEGIN DOCKER LAB" {
      if (inside) exit 2
      inside = 1
      next
    }
    $0 == "# END DOCKER LAB" {
      if (!inside) exit 2
      inside = 0
      next
    }
    !inside { print }
    END { if (inside) exit 2 }
  ' /etc/hosts > "$TEMP_FILE"; then
    echo "Erro: bloco gerenciado do Docker Lab está malformado em /etc/hosts." >&2
    cleanup
    return 1
  fi

  {
    printf '\n# BEGIN DOCKER LAB\n'
    cat -- "$HOSTS_FILE"
    printf '# END DOCKER LAB\n'
  } >> "$TEMP_FILE"

  if ! command -v sudo >/dev/null 2>&1; then
    echo "Erro: sudo é necessário para atualizar /etc/hosts." >&2
    cleanup
    return 1
  fi

  # O grupo do root é "wheel" no macOS e "root" no Linux.
  if ! sudo install -o root -g "$(id -gn root)" -m 644 "$TEMP_FILE" /etc/hosts; then
    cleanup
    return 1
  fi
  cleanup

  if [[ "$PLATFORM" == "macos" ]]; then
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder
  fi
  echo "Hosts locais (/etc/hosts) atualizados."
}

update_windows_hosts() {
  if ! command -v powershell.exe >/dev/null 2>&1; then
    if [[ "$MODE" == "windows" ]]; then
      echo "Erro: powershell.exe não foi encontrado. Execute este script no WSL." >&2
      return 1
    fi
    echo "Windows hosts não atualizado: powershell.exe não está disponível."
    return 0
  fi

  local windows_script
  if command -v wslpath >/dev/null 2>&1; then
    windows_script="$(wslpath -w "$SCRIPT_DIR/update-hosts-windows.ps1")"
  elif command -v cygpath >/dev/null 2>&1; then
    windows_script="$(cygpath -w "$SCRIPT_DIR/update-hosts-windows.ps1")"
  else
    windows_script="$SCRIPT_DIR/update-hosts-windows.ps1"
  fi

  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_script"
}

case "$MODE" in
  both)
    update_local_hosts
    if [[ "$PLATFORM" == "wsl" || "$PLATFORM" == "gitbash" ]]; then
      update_windows_hosts
    fi
    ;;
  local) update_local_hosts ;;
  windows) update_windows_hosts ;;
esac
EOF_HOSTS_UPDATE
chmod +x "$BASE/scripts/update-hosts.sh"

cat > "$BASE/scripts/update-hosts-windows.ps1" <<'EOF_WINDOWS_HOSTS'
$ErrorActionPreference = 'Stop'
$beginMarker = '# BEGIN DOCKER LAB'
$endMarker = '# END DOCKER LAB'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $tempDirectory = Join-Path $env:TEMP ("docker-lab-hosts-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDirectory | Out-Null
    try {
        $elevatedScriptDirectory = Join-Path $tempDirectory 'scripts'
        New-Item -ItemType Directory -Path $elevatedScriptDirectory | Out-Null
        $elevatedScript = Join-Path $elevatedScriptDirectory 'update-hosts-windows.ps1'
        $elevatedHosts = Join-Path $tempDirectory 'hosts-lab.txt'
        Copy-Item -LiteralPath $PSCommandPath -Destination $elevatedScript
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\hosts-lab.txt') -Destination $elevatedHosts
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $elevatedScript
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Windows hosts update failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force
    }
    exit 0
}

$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$entriesPath = Join-Path $PSScriptRoot '..\hosts-lab.txt'
$entries = @(Get-Content -LiteralPath $entriesPath | Where-Object { $_.Trim() -ne '' })
if ($entries.Count -eq 0) {
    throw "The hosts file is empty: $entriesPath"
}
foreach ($entry in $entries) {
    if ($entry -notmatch '^\s*127\.0\.0\.1\s+[A-Za-z0-9.-]+\s*$') {
        throw "Invalid hosts entry: $entry"
    }
}

$updatedLines = [System.Collections.Generic.List[string]]::new()
$insideBlock = $false
foreach ($line in [System.IO.File]::ReadAllLines($hostsPath)) {
    if ($line -eq $beginMarker) {
        if ($insideBlock) { throw 'Nested DOCKER LAB blocks in hosts file.' }
        $insideBlock = $true
        continue
    }
    if ($line -eq $endMarker) {
        if (-not $insideBlock) { throw 'End marker without a start marker in hosts file.' }
        $insideBlock = $false
        continue
    }
    if (-not $insideBlock) { $updatedLines.Add($line) }
}
if ($insideBlock) { throw 'DOCKER LAB block has no end marker in hosts file.' }
if ($updatedLines.Count -gt 0 -and $updatedLines[$updatedLines.Count - 1] -ne '') {
    $updatedLines.Add('')
}
$updatedLines.Add($beginMarker)
foreach ($entry in $entries) { $updatedLines.Add($entry) }
$updatedLines.Add($endMarker)

$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($hostsPath, $updatedLines.ToArray(), $encoding)
Write-Output 'Hosts do Windows atualizados.'
EOF_WINDOWS_HOSTS

printf "\nInfraestrutura criada com %s.\n" "$LAB_ENGINE"
printf "\nConfigurações: %s\nDados persistentes: %s\nBackups: %s\n" "$BASE" "$DATA" "$BACKUPS"
if [[ "$(lab_platform)" == "wsl" ]]; then
  printf "\nPara atualizar os hosts do WSL e do Windows, execute:\n"
else
  printf "\nPara atualizar o arquivo de hosts, execute:\n"
fi
printf "%s/scripts/update-hosts.sh\n" "$BASE"
printf "\nExecute:\n"
printf "%s/scripts/start-all.sh\n" "$BASE"

if should_create_service "ollama"; then
  printf "\nOllama: modo %s, acessado pelos containers em %s\n" "$OLLAMA_MODE" "$OLLAMA_URL"
  if [[ -f "$BASE/ollama/EXTERNAL.txt" ]]; then
    sed 's/^/  /' "$BASE/ollama/EXTERNAL.txt"
  fi
  printf "Depois de subir o Ollama, baixe os modelos (%s e nomic-embed-text):\n" "$LLM_MODEL"
  printf "%s/ollama/pull-models.sh\n" "$BASE"
fi
