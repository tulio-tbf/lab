# Guia de administração do Docker Lab

Este guia considera que os comandos serão executados no WSL ou em um terminal
Linux e que o laboratório está localizado em `/mnt/d/lab/docker`.

```bash
cd /mnt/d/lab/docker
```

> As credenciais incluídas neste laboratório são destinadas somente ao
> desenvolvimento local. Consulte os arquivos `docker-compose.yml` antes de
> executar comandos de banco de dados caso elas tenham sido alteradas.

## Gerenciar todo o laboratório

Iniciar todos os serviços:

```bash
./scripts/start-all.sh
```

Parar e remover os containers e redes Compose:

```bash
./scripts/stop-all.sh
```

Listar containers em execução:

```bash
docker ps
```

Listar também os containers parados:

```bash
docker ps -a
```

Exibir consumo de CPU e memória:

```bash
docker stats
```

Verificar a rede compartilhada:

```bash
docker network inspect infra-network
```

## Gerenciar um serviço

Substitua `<servico>` pelo diretório desejado, por exemplo `wordpress`,
`wordpress-db`, `evolution-api` ou `evolution-db`.

```bash
cd /mnt/d/lab/docker/<servico>
```

Criar ou iniciar:

```bash
docker compose up -d
```

Ver o estado:

```bash
docker compose ps
```

Ver logs continuamente:

```bash
docker compose logs -f --tail=200
```

Reiniciar:

```bash
docker compose restart
```

Parar sem remover:

```bash
docker compose stop
```

Iniciar um serviço que está parado:

```bash
docker compose start
```

Parar e remover o container:

```bash
docker compose down
```

Validar o arquivo Compose:

```bash
docker compose config
```

Baixar a imagem configurada e recriar o container:

```bash
docker compose pull
docker compose up -d --force-recreate
```

> Antes de atualizar imagens de banco de dados, faça backup e confira as notas
> de migração da versão. Não use `docker compose down -v` neste laboratório sem
> entender o impacto, pois essa opção remove volumes nomeados.

Os bancos usam os volumes Docker nomeados `wordpress-db-data`,
`mautic-db-data`, `n8n-db-data` e `evolution-db-data`. Isso evita problemas de
permissão dos bancos em diretórios Windows montados no WSL.

## Inspecionar e diagnosticar containers

Substitua `<container>` pelo nome apresentado por `docker ps -a`.

```bash
docker inspect <container>
docker logs --tail=200 <container>
docker logs -f <container>
docker top <container>
docker port <container>
docker diff <container>
docker stats <container>
```

Ver processos e eventos do Docker:

```bash
docker system events
docker info
docker version
```

Ver uso de disco:

```bash
docker system df
docker system df -v
```

## Abrir um shell dentro dos containers

A opção `-it` cria um terminal interativo. Use `exit` para sair.

```bash
docker exec -it traefik sh
docker exec -it wordpress sh
docker exec -it wordpress-db sh
docker exec -it mautic sh
docker exec -it mautic-db sh
docker exec -it n8n sh
docker exec -it n8n-db sh
docker exec -it redis sh
docker exec -it minio sh
docker exec -it portainer sh
docker exec -it adminer sh
docker exec -it pgadmin sh
docker exec -it mailhog sh
docker exec -it evolution-api sh
docker exec -it evolution-db sh
```

Algumas imagens mínimas não possuem shell ou ferramentas administrativas. Se
um comando retornar `executable file not found`, faça a manutenção por
`docker logs`, pela interface web ou por um container auxiliar ligado à
`infra-network`.

## Manutenção por aplicação

### Traefik

```bash
docker logs -f --tail=200 traefik
docker exec traefik traefik version
docker inspect traefik
```

Painel: <http://traefik.lab.local>

### WordPress

Shell e arquivos da instalação:

```bash
docker exec -it wordpress sh
docker exec wordpress ls -la /var/www/html
```

Executar PHP e verificar módulos:

```bash
docker exec wordpress php -v
docker exec wordpress php -m
```

Os arquivos persistentes também estão disponíveis no host:

```bash
cd /mnt/d/lab/docker/wordpress/files
```

Site: <http://wordpress.lab.local>

O serviço registra `wordpress.lab.local` como alias na rede Docker
`infra-network`. Portanto, essa mesma URL pode ser usada nas credenciais do
n8n e em integrações executadas por outros containers do laboratório.

O laboratório define `WP_ENVIRONMENT_TYPE` como `local`. Isso permite criar
Application Passwords para integrações REST em HTTP. Em produção, utilize HTTPS
e altere o tipo de ambiente para `production`.

### Banco do WordPress — MySQL

O WordPress e o MySQL leem a senha compartilhada do arquivo:

```text
/mnt/d/lab/docker/wordpress/secrets/db_password
```

Para trocar a senha, altere primeiro o usuário no MySQL, atualize o arquivo
acima e recrie os containers `wordpress-db` e `wordpress`.

Abrir o cliente MySQL:

```bash
docker exec -it wordpress-db mysql -uwordpress -pwordpress123 wordpress
```

Verificar disponibilidade:

```bash
docker exec wordpress-db mysqladmin ping -uroot -proot123
```

Criar backup:

```bash
docker exec wordpress-db mysqldump -uwordpress -pwordpress123 wordpress > wordpress-backup.sql
```

Restaurar backup:

```bash
docker exec -i wordpress-db mysql -uwordpress -pwordpress123 wordpress < wordpress-backup.sql
```

### Mautic

```bash
docker exec -it mautic sh
docker exec mautic php /var/www/html/bin/console about
docker exec mautic php /var/www/html/bin/console cache:clear
docker exec mautic php /var/www/html/bin/console mautic:segments:update
docker exec mautic php /var/www/html/bin/console mautic:campaigns:update
docker exec mautic php /var/www/html/bin/console mautic:campaigns:trigger
```

O código da aplicação vem da imagem e não deve receber um bind mount sobre
`/var/www/html`, pois isso ocultaria o Mautic instalado. Configurações,
arquivos de mídia e logs persistem nos volumes nomeados `mautic-config-data`,
`mautic-media-files-data`, `mautic-media-images-data` e `mautic-logs-data`.
As variáveis de conexão esperadas pela imagem incluem `MAUTIC_DB_PORT` e
`MAUTIC_DB_DATABASE`; não utilize o nome antigo `MAUTIC_DB_NAME`.
O laboratório fixa a imagem em `mautic/mautic:7.1.2-apache` para evitar
alterações e regressões inesperadas da tag flutuante `latest`.

Aplicação: <http://mautic.lab.local>

### Banco do Mautic — MariaDB

```bash
docker exec -it mautic-db mariadb -umautic -pmautic123 mautic
docker exec mautic-db mariadb-admin ping -uroot -proot123
```

Backup e restauração:

```bash
docker exec mautic-db mariadb-dump -umautic -pmautic123 mautic > mautic-backup.sql
docker exec -i mautic-db mariadb -umautic -pmautic123 mautic < mautic-backup.sql
```

### n8n

```bash
docker exec -it n8n sh
docker exec n8n n8n --version
docker logs -f --tail=200 n8n
```

O diretório do host `/mnt/d/lab/docker/n8n/arquivos` fica disponível dentro
do container como `/data/arquivos`. Nos nós **Read/Write Files from Disk**,
**Local File Trigger** e similares, sempre utilize o caminho interno:

```text
/data/arquivos/nome-do-arquivo.ext
```

O Compose define `N8N_RESTRICT_FILE_ACCESS_TO=/data/arquivos`, restringindo os
nós de arquivo a esse diretório.

Aplicação: <http://n8n.lab.local>

### Banco do n8n — PostgreSQL

```bash
docker exec -it n8n-db psql -U n8n -d n8n
docker exec n8n-db pg_isready -U n8n -d n8n
```

Backup e restauração:

```bash
docker exec n8n-db pg_dump -U n8n -d n8n -Fc > n8n-backup.dump
docker exec -i n8n-db pg_restore -U n8n -d n8n --clean --if-exists < n8n-backup.dump
```

### Redis

```bash
docker exec -it redis redis-cli
docker exec redis redis-cli PING
docker exec redis redis-cli INFO
docker exec redis redis-cli DBSIZE
```

Evite executar `FLUSHDB` ou `FLUSHALL` sem um backup e confirmação do banco
selecionado.

### MinIO

```bash
docker logs -f --tail=200 minio
docker inspect minio
```

Console: <http://minio.lab.local>

Para administrar pela CLI, use um container temporário:

```bash
docker run --rm -it --network infra-network minio/mc \
  alias set local http://minio:9000 admin admin123
```

### Portainer

```bash
docker logs -f --tail=200 portainer
docker inspect portainer
```

Interface: <http://portainer.lab.local>

### Adminer

```bash
docker logs -f --tail=200 adminer
docker inspect adminer
```

Interface: <http://adminer.lab.local>

Use como servidor o nome do container do banco, como `wordpress-db`,
`mautic-db`, `n8n-db` ou `evolution-db`.

### pgAdmin

```bash
docker logs -f --tail=200 pgadmin
docker inspect pgadmin
```

Interface: <http://pgadmin.lab.local>

Ao cadastrar um servidor PostgreSQL, use `n8n-db` ou `evolution-db` como host,
conforme o banco desejado.

### MailHog

```bash
docker logs -f --tail=200 mailhog
docker inspect mailhog
```

Interface: <http://mailhog.lab.local>

O servidor SMTP fica disponível para os outros containers como `mailhog:1025`.

### Evolution API

```bash
docker exec -it evolution-api sh
docker logs -f --tail=200 evolution-api
docker inspect evolution-api
```

O laboratório utiliza `evoapicloud/evolution-api:v2.3.7` e força a resolução
DNS IPv4 com `NODE_OPTIONS=--dns-result-order=ipv4first`, evitando loops de
conexão do Baileys observados em versões antigas no Docker/WSL.

Aplicação: <http://evolution-api.lab.local>

Depois de qualquer alteração no Compose:

```bash
cd /mnt/d/lab/docker/evolution-api
docker compose config
docker compose up -d --force-recreate
```

### Banco da Evolution API — PostgreSQL

Abrir o cliente e verificar a conexão:

```bash
docker exec -it evolution-db psql -U postgres -d evolution
docker exec evolution-db pg_isready -U postgres -d evolution
```

Listar tabelas sem abrir um terminal interativo:

```bash
docker exec evolution-db psql -U postgres -d evolution -c '\dt'
```

Backup:

```bash
docker exec evolution-db pg_dump -U postgres -d evolution -Fc > evolution-backup.dump
```

Restauração:

```bash
docker exec -i evolution-db pg_restore \
  -U postgres -d evolution --clean --if-exists < evolution-backup.dump
```

## Copiar arquivos entre host e container

Copiar do container para o diretório atual:

```bash
docker cp <container>:/caminho/no/container ./destino
```

Copiar do host para o container:

```bash
docker cp ./arquivo <container>:/caminho/no/container/
```

Confira proprietário e permissões depois de copiar arquivos para diretórios da
aplicação.

## Sequência recomendada para diagnóstico

```bash
docker ps -a
docker compose -f /mnt/d/lab/docker/<servico>/docker-compose.yml config
docker logs --tail=200 <container>
docker inspect <container>
docker network inspect infra-network
docker stats <container>
```

Quando uma aplicação depende de banco ou Redis, verifique primeiro o serviço
dependente. Por exemplo:

```bash
docker exec evolution-db pg_isready -U postgres -d evolution
docker exec redis redis-cli PING
docker logs --tail=200 evolution-api
```
