#!/bin/bash

set -e

BASE=/mnt/d/docker
DATA=/mnt/d/docker/data
NETWORK=infra-network

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

mkdir -p "$BASE/scripts"

if should_create_service "traefik"; then
  mkdir -p "$BASE/traefik"
fi

if should_create_service "wordpress" || should_create_service "wordpress-db"; then
  mkdir -p "$BASE/wordpress" "$BASE/wordpress/files"
fi

if should_create_service "mautic" || should_create_service "mautic-db"; then
  mkdir -p "$BASE/mautic" "$BASE/mautic/files"
fi

if should_create_service "n8n" || should_create_service "n8n-db"; then
  mkdir -p "$BASE/n8n" "$BASE/n8n/data"
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
  mkdir -p "$BASE/evolution-api"
fi

mkdir -p "$DATA"

if should_create_service "wordpress-db"; then
  mkdir -p "$DATA/wordpress-db"
fi

if should_create_service "mautic-db"; then
  mkdir -p "$DATA/mautic-db"
fi

if should_create_service "n8n-db"; then
  mkdir -p "$DATA/n8n-db"
fi

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

if should_create_service "evolution-api" || should_create_service "evolution-db"; then
  mkdir -p "$DATA/evolution-api" "$DATA/evolution-db"
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
      MYSQL_PASSWORD: wordpress123

    volumes:
      - /mnt/d/docker/data/wordpress-db:/var/lib/mysql

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_WORDPRESS_DB
fi

#############################################
# WORDPRESS
#############################################

if should_create_service "wordpress"; then
cat > "$BASE/wordpress/docker-compose.yml" <<'EOF_WORDPRESS'
services:
  wordpress:
    image: wordpress:latest

    container_name: wordpress

    restart: unless-stopped

    environment:
      WORDPRESS_DB_HOST: wordpress-db
      WORDPRESS_DB_NAME: wordpress
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress123

    volumes:
      - /mnt/d/docker/wordpress/files:/var/www/html/

    labels:
      - traefik.enable=true
      - traefik.http.routers.wordpress.rule=Host(`wordpress.lab.local`)
      - traefik.http.services.wordpress.loadbalancer.server.port=80

    networks:
      - infra

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
      - /mnt/d/docker/data/mautic-db:/var/lib/mysql

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_MAUTIC_DB
fi

#############################################
# MAUTIC
#############################################

if should_create_service "mautic"; then
cat > "$BASE/mautic/docker-compose.yml" <<'EOF_MAUTIC'
services:
  mautic:
    image: mautic/mautic:latest

    container_name: mautic

    restart: unless-stopped

    environment:
      MAUTIC_DB_HOST: mautic-db
      MAUTIC_DB_USER: mautic
      MAUTIC_DB_PASSWORD: mautic123
      MAUTIC_DB_NAME: mautic

    volumes:
      - /mnt/d/docker/mautic/files:/var/www/html/

    labels:
      - traefik.enable=true
      - traefik.http.routers.mautic.rule=Host(`mautic.lab.local`)
      - traefik.http.services.mautic.loadbalancer.server.port=80

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
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
      - /mnt/d/docker/data/n8n-db:/var/lib/postgresql/data

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_N8N_DB
fi

#############################################
# N8N
#############################################

if should_create_service "n8n"; then
cat > "$BASE/n8n/docker-compose.yml" <<'EOF_N8N'
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

    volumes:
      - /mnt/d/docker/n8n/data:/home/node/

    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(`n8n.lab.local`)
      - traefik.http.services.n8n.loadbalancer.server.port=5678

    networks:
      - infra

networks:
  infra:
    external: true
    name: infra-network
EOF_N8N
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
      - /mnt/d/docker/data/redis:/data

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
      - /mnt/d/docker/data/minio:/data

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
      - /mnt/d/docker/data/portainer:/data

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
      - "8025:8025"
      - "1025:1025"

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
      PGADMIN_DEFAULT_EMAIL: admin@lab.localdomain
      PGADMIN_DEFAULT_PASSWORD: admin123

    volumes:
      - /mnt/d/docker/data/pgadmin:/var/lib/pgadmin

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
EOF_PGADMIN
fi

#############################################
# EVOLUTION API
#############################################

if should_create_service "evolution-api" || should_create_service "evolution-db"; then
cat > "$BASE/evolution-api/docker-compose.yml" <<'EOF_EVOLUTION'
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

  evolution-api:
    image: evoapicloud/evolution-api:v2.1.1
    container_name: evolution-api
    restart: unless-stopped

    depends_on:
      evolution-db:
        condition: service_healthy

    ports:
      - "8080:8080"

    environment:
      AUTHENTICATION_API_KEY: change-me
      SERVER_URL: http://evolution-api.lab.local
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
      - /mnt/d/docker/data/evolution-api:/evolution/instances

    labels:
      - traefik.enable=true
      - traefik.http.routers.evolution-api.rule=Host(`evolution-api.lab.local`)
      - traefik.http.routers.evolution-api.entrypoints=web
      - traefik.http.routers.evolution-api.service=evolution-api
      - traefik.http.services.evolution-api.loadbalancer.server.port=8080

    networks:
      - infra

volumes:
  evolution-db-data:

networks:
  infra:
    external: true
    name: infra-network
EOF_EVOLUTION
fi

#############################################
# START-ALL
#############################################

START_SERVICES=()
for service in traefik wordpress-db mautic-db n8n-db redis minio wordpress mautic n8n portainer adminer pgadmin mailhog evolution-db evolution-api; do
  if should_create_service "$service"; then
    START_SERVICES+=("$service")
  fi
done

cat > "$BASE/scripts/start-all.sh" <<'EOF_START'
#!/bin/bash

set -e

BASE=/mnt/d/docker

SERVICES=(
EOF_START
for service in "${START_SERVICES[@]}"; do
  printf '  %s\n' "$service" >> "$BASE/scripts/start-all.sh"
done
cat >> "$BASE/scripts/start-all.sh" <<'EOF_START_END'
)

for service in "${SERVICES[@]}"
do
  echo "Subindo $service"
  if [ "$service" = "evolution-db" ]; then
    cd "$BASE/evolution-api"
  else
    cd "$BASE/$service"
  fi
  docker compose up -d
done

docker ps
EOF_START_END

chmod +x "$BASE/scripts/start-all.sh"

#############################################
# STOP-ALL
#############################################

STOP_SERVICES=()
for service in "${START_SERVICES[@]}"; do
  STOP_SERVICES+=("$service")
done

cat > "$BASE/scripts/stop-all.sh" <<'EOF_STOP'
#!/bin/bash

set -e

BASE=/mnt/d/docker

SERVICES=(
EOF_STOP
for service in "${STOP_SERVICES[@]}"; do
  printf '  %s\n' "$service" >> "$BASE/scripts/stop-all.sh"
done
cat >> "$BASE/scripts/stop-all.sh" <<'EOF_STOP_END'
)

for service in "${SERVICES[@]}"
do
  echo "Parando $service"
  if [ "$service" = "evolution-db" ]; then
    cd "$BASE/evolution-api"
  else
    cd "$BASE/$service"
  fi
  docker compose down
done
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

printf "\nInfraestrutura criada com sucesso.\n"
printf "\nAdicione os hosts ao arquivo hosts do Windows.\n"
printf "\nExecute:\n"
printf "%s/scripts/start-all.sh\n" "$BASE"
