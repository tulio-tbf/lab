#!/bin/bash

set -e

BASE=/mnt/d/docker

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
  if [ "$service" = "evolution-db" ]; then
    cd "$BASE/evolution-api"
  else
    cd "$BASE/$service"
  fi
  docker compose up -d
done

docker ps
