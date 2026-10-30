#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="${LAB_BASE:-$HOME/docker-shared}"
DATA="${LAB_DATA:-$HOME/lab-data}"
BACKUPS="${LAB_BACKUPS:-$HOME/backups}"
NETWORK="infra-network"

usage() {
  cat <<'EOF'
Uso: ./create-lab.sh [opções]

  -b, --base DIRETÓRIO   Diretório das configurações geradas (padrão: ~/docker-shared)
  -d, --data DIRETÓRIO   Diretório dos dados persistentes (padrão: ~/lab-data)
  -o, --backups DIRETÓRIO Diretório dos backups (padrão: ~/backups)
  -h, --help             Exibe esta ajuda

As opções também podem ser definidas por LAB_BASE, LAB_DATA e LAB_BACKUPS.
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

yaml_path() {
  # Aspas simples tornam seguros espaços, dois-pontos e caracteres especiais.
  printf "'%s'" "${1//\'/\'\'}"
}

printf "\nEscolha o que deseja criar:\n"
printf "  A = criar todos os serviços\n"
printf "  ou informe os serviços desejados separados por espaço\n"
printf "Serviços disponíveis: traefik wordpress wordpress-db mautic mautic-db n8n n8n-db redis minio portainer adminer pgadmin mailhog evolution-db evolution-api\n"
read -r -p "Opção: " answer

if [[ -z "$answer" ]]; then
  answer="A"
fi

answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

if [[ "$answer" == "a" || "$answer" == "all" ]]; then
  SELECTED_SERVICES=(traefik wordpress wordpress-db mautic mautic-db n8n n8n-db redis minio portainer adminer pgadmin mailhog evolution-db evolution-api)
else
  SELECTED_SERVICES=()
  for token in $answer; do
    case "$token" in
      traefik|wordpress|wordpress-db|mautic|mautic-db|n8n|n8n-db|redis|minio|portainer|adminer|pgadmin|mailhog|evolution-db|evolution-api)
        SELECTED_SERVICES+=("$token")
        ;;
      *)
        echo "Serviço inválido: $token"
        exit 1
        ;;
    esac
  done
fi

declare -A DEPENDENCIES=(
  [traefik]=""
  [wordpress-db]=""
  [wordpress]="wordpress-db traefik"
  [mautic-db]=""
  [mautic]="mautic-db traefik"
  [n8n-db]=""
  [n8n]="n8n-db traefik"
  [redis]=""
  [minio]="traefik"
  [portainer]="traefik"
  [adminer]="traefik"
  [pgadmin]="traefik"
  [mailhog]="traefik"
  [evolution-db]=""
  [evolution-api]="evolution-db redis traefik"
)

service_requires() {
  local service="$1"
  local target="$2"
  local dep

  if [[ "$service" == "$target" ]]; then
    return 0
  fi

  for dep in ${DEPENDENCIES[$service]}; do
    if [[ "$dep" == "$target" ]] || service_requires "$dep" "$target"; then
      return 0
    fi
  done

  return 1
}

should_create_service() {
  local service="$1"
  local selected

  for selected in "${SELECTED_SERVICES[@]}"; do
    if service_requires "$selected" "$service"; then
      return 0
    fi
  done

  return 1
}

mkdir -p "$BASE/scripts" "$BASE/networks" "$BASE/certificates" "$BASE/templates"
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
fi

if should_create_service "mautic" || should_create_service "mautic-db"; then
  mkdir -p "$BASE/mautic" "$BASE/mautic-db"
fi

if should_create_service "n8n" || should_create_service "n8n-db"; then
  mkdir -p "$BASE/n8n" "$BASE/n8n-db" "$DATA/n8n/data" "$DATA/n8n/arquivos"
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

docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK"

#############################################
# TRAEFIK
#############################################

if should_create_service "traefik"; then
cat > "$BASE/traefik/docker-compose.yml" <<'EOF_TRAEFIK'
services:
  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped

    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --api.dashboard=true
      - --api.insecure=true

    ports:
      - "80:80"
      - "8088:8080"

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

    labels:
      - traefik.enable=true
      - traefik.http.routers.traefik.rule=Host(`traefik.lab.local`)
      - traefik.http.routers.traefik.entrypoints=web
      - traefik.http.routers.traefik.service=api@internal
      - traefik.http.routers.traefik.middlewares=dashboard
      - traefik.http.middlewares.dashboard.redirectregex.regex=^http://traefik\.lab\.local/?$
      - traefik.http.middlewares.dashboard.redirectregex.replacement=http://traefik.lab.local/dashboard/

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
    image: mysql:8
    container_name: wordpress-db

    restart: unless-stopped

    environment:
      MYSQL_ROOT_PASSWORD: root123
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD_FILE: /run/secrets/wordpress_db_password

    volumes:
      - wordpress-db-data:/var/lib/mysql
      - $(yaml_path "$DATA/wordpress/secrets/db_password:/run/secrets/wordpress_db_password:ro")

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
cat > "$BASE/wordpress/docker-compose.yml" <<EOF_WORDPRESS
services:
  wordpress:
    image: wordpress:latest

    container_name: wordpress

    restart: unless-stopped

    environment:
      WORDPRESS_DB_HOST: wordpress-db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD_FILE: /run/secrets/wordpress_db_password
      WORDPRESS_ENVIRONMENT_TYPE: local

    volumes:
      - $(yaml_path "$DATA/wordpress/files:/var/www/html/")
      - $(yaml_path "$DATA/wordpress/secrets/db_password:/run/secrets/wordpress_db_password:ro")

    labels:
      - traefik.enable=true
      - traefik.http.routers.wordpress.rule=Host(\`wordpress.lab.local\`)
      - traefik.http.services.wordpress.loadbalancer.server.port=80

    networks:
      infra:
        aliases:
          - wordpress.lab.local

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
    image: mariadb:11

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
cat > "$BASE/mautic/docker-compose.yml" <<EOF_MAUTIC
services:
  mautic:
    image: mautic/mautic:7.1.2-apache

    container_name: mautic

    restart: unless-stopped

    environment:
      MAUTIC_DB_HOST: mautic-db
      MAUTIC_DB_PORT: "3306"
      MAUTIC_DB_USER: mautic
      MAUTIC_DB_PASSWORD: mautic123
      MAUTIC_DB_DATABASE: mautic

    volumes:
      - mautic-config-data:/var/www/html/config
      - mautic-media-files-data:/var/www/html/docroot/media/files
      - mautic-media-images-data:/var/www/html/docroot/media/images
      - mautic-logs-data:/var/www/html/var/logs

    labels:
      - traefik.enable=true
      - traefik.http.routers.mautic.rule=Host(\`mautic.lab.local\`)
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
# N8N DB
#############################################

if should_create_service "n8n-db"; then
cat > "$BASE/n8n-db/docker-compose.yml" <<EOF_N8N_DB
services:
  n8n-db:
    image: postgres:17

    container_name: n8n-db

    restart: unless-stopped

    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: n8n123

    volumes:
      - n8n-db-data:/var/lib/postgresql/data

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network

volumes:
  n8n-db-data:
    name: n8n-db-data
EOF_N8N_DB
fi

#############################################
# N8N
#############################################

if should_create_service "n8n"; then
cat > "$BASE/n8n/docker-compose.yml" <<EOF_N8N
services:
  n8n:
    image: n8nio/n8n:latest

    container_name: n8n

    restart: unless-stopped

    environment:
      N8N_HOST: n8n.lab.local
      N8N_PROTOCOL: http
      N8N_SECURE_COOKIE: "false"
      WEBHOOK_URL: http://n8n.lab.local/
      N8N_RESTRICT_FILE_ACCESS_TO: /data/arquivos

    volumes:
      - $(yaml_path "$DATA/n8n/data:/home/node/")
      - $(yaml_path "$DATA/n8n/arquivos:/data/arquivos")

    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(\`n8n.lab.local\`)
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

if ! docker info >/dev/null 2>&1; then
  echo "Erro: o Docker Engine não está acessível neste WSL." >&2
  echo "Verifique o systemd e execute: sudo systemctl start docker" >&2
  exit 1
fi

echo "Baixando a imagem atual do n8n..."
if ! docker compose pull; then
  echo "Erro: a imagem não foi baixada; o container não será recriado." >&2
  echo "Verifique a conectividade IPv4/DNS do Docker Engine e tente novamente." >&2
  exit 1
fi

echo "Recriando o container n8n..."
docker compose up -d --force-recreate
docker exec n8n n8n --version
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
    image: redis:latest

    container_name: redis

    restart: unless-stopped

    volumes:
      - $(yaml_path "$DATA/redis:/data")

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
    image: minio/minio

    container_name: minio

    command: server /data --console-address ":9001"

    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: admin123

    volumes:
      - $(yaml_path "$DATA/minio:/data")

    labels:
      - traefik.enable=true
      - traefik.http.routers.minio.rule=Host(\`minio.lab.local\`)
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
    image: portainer/portainer-ce:latest

    container_name: portainer

    restart: unless-stopped

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $(yaml_path "$DATA/portainer:/data")

    labels:
      - traefik.enable=true
      - traefik.http.routers.portainer.rule=Host(\`portainer.lab.local\`)
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
cat > "$BASE/mailhog/docker-compose.yml" <<'EOF_MAILHOG'
services:
  mailhog:
    image: mailhog/mailhog:latest

    container_name: mailhog

    restart: unless-stopped

    ports:
      - "8026:8025"
      - "1026:1025"

    labels:
      - traefik.enable=true
      - traefik.http.routers.mailhog.rule=Host(`mailhog.lab.local`)
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
cat > "$BASE/adminer/docker-compose.yml" <<'EOF_ADMINER'
services:
  adminer:
    image: adminer

    container_name: adminer

    restart: unless-stopped

    labels:
      - traefik.enable=true
      - traefik.http.routers.adminer.rule=Host(`adminer.lab.local`)
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
    image: dpage/pgadmin4

    container_name: pgadmin

    restart: unless-stopped

    environment:
      PGADMIN_DEFAULT_EMAIL: admin@example.com
      PGADMIN_DEFAULT_PASSWORD: admin123

    volumes:
      - pgadmin-data:/var/lib/pgadmin

    labels:
      - traefik.enable=true
      - traefik.http.routers.pgadmin.rule=Host(\`pgadmin.lab.local\`)
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
    image: postgres:16-alpine
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
cat > "$BASE/evolution-api/docker-compose.yml" <<EOF_EVOLUTION_API
services:
  evolution-api:
    image: evoapicloud/evolution-api:v2.3.7
    container_name: evolution-api
    restart: unless-stopped

    ports:
      - "8080:8080"

    environment:
      AUTHENTICATION_API_KEY: change-me
      SERVER_URL: http://evolution-api.lab.local
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
      - $(yaml_path "$DATA/evolution-api:/evolution/instances")

    labels:
      - traefik.enable=true
      - traefik.http.routers.evolution-api.rule=Host(\`evolution-api.lab.local\`)
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
# START-ALL
#############################################

START_SERVICES=(traefik wordpress-db mautic-db n8n-db redis wordpress mautic n8n portainer adminer pgadmin mailhog evolution-db evolution-api)

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

SERVICES=(
EOF_START
for service in "${START_SERVICES[@]}"; do
  printf '  %s\n' "$service" >> "$BASE/scripts/start-all.sh"
done
cat >> "$BASE/scripts/start-all.sh" <<'EOF_START_END'
)

echo "Ignorando minio: imagem configurada indisponível; escolha uma alternativa antes de reativá-lo."

FAILED_SERVICES=()

for service in "${SERVICES[@]}"
do
  if [[ ! -f "$BASE/$service/docker-compose.yml" ]]; then
    echo "Ignorando $service: arquivo docker-compose.yml não encontrado em $BASE/$service"
    continue
  fi

  echo "Subindo $service"
  if ! (cd -- "$BASE/$service" && docker compose up -d); then
    FAILED_SERVICES+=("$service")
  fi
done

docker ps

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
STOP_SERVICES+=(minio)

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

if ! docker info >/dev/null 2>&1; then
  echo "Erro: o Docker Engine não está acessível neste WSL." >&2
  echo "Inicie o systemd e o serviço Docker antes de continuar:" >&2
  echo "  systemctl is-system-running" >&2
  echo "  sudo systemctl start docker" >&2
  echo "Se o WSL não usar systemd, habilite [boot] systemd=true em /etc/wsl.conf e execute 'wsl --shutdown' no PowerShell." >&2
  exit 1
fi

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
  if ! (cd -- "$BASE/$service" && docker compose down); then
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

cat > "$BASE/hosts-lab.txt" <<'EOF_HOSTS'
127.0.0.1 traefik.lab.local
EOF_HOSTS

if should_create_service "wordpress"; then
  printf '127.0.0.1 wordpress.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "mautic"; then
  printf '127.0.0.1 mautic.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "n8n"; then
  printf '127.0.0.1 n8n.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "minio"; then
  printf '127.0.0.1 minio.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "portainer"; then
  printf '127.0.0.1 portainer.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "adminer"; then
  printf '127.0.0.1 adminer.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "pgadmin"; then
  printf '127.0.0.1 pgadmin.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "mailhog"; then
  printf '127.0.0.1 mailhog.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

if should_create_service "evolution-api"; then
  printf '127.0.0.1 evolution-api.lab.local\n' >> "$BASE/hosts-lab.txt"
fi

cat > "$BASE/scripts/update-hosts.sh" <<'EOF_HOSTS_UPDATE'
#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
HOSTS_FILE="$BASE/hosts-lab.txt"
MODE="both"
TEMP_FILE=""

cleanup() {
  if [[ -n "$TEMP_FILE" ]]; then
    rm -f -- "$TEMP_FILE"
    TEMP_FILE=""
  fi
}
trap cleanup EXIT

usage() {
  echo "Uso: $0 [--wsl-only | --windows-only]"
}

while (($#)); do
  case "$1" in
    --wsl-only) MODE="wsl"; shift ;;
    --windows-only) MODE="windows"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Erro: opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -s "$HOSTS_FILE" ]]; then
  echo "Erro: arquivo de hosts ausente ou vazio: $HOSTS_FILE" >&2
  exit 1
fi

update_wsl_hosts() {
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

  if ! sudo install -o root -g root -m 644 "$TEMP_FILE" /etc/hosts; then
    cleanup
    return 1
  fi
  cleanup
  echo "Hosts do WSL atualizados."
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
    update_wsl_hosts
    update_windows_hosts
    ;;
  wsl) update_wsl_hosts ;;
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

printf "\nInfraestrutura criada com sucesso.\n"
printf "\nConfigurações: %s\nDados persistentes: %s\nBackups: %s\n" "$BASE" "$DATA" "$BACKUPS"
printf "\nPara atualizar os hosts do WSL e do Windows, execute:\n"
printf "%s/scripts/update-hosts.sh\n" "$BASE"
printf "\nExecute:\n"
printf "%s/scripts/start-all.sh\n" "$BASE"
