# lab
Este repositório contém uma infraestrutura local baseada em Docker Compose para hospedar vários serviços de apoio e aplicações web em um ambiente de laboratório.

# Ambiente Docker Lab

Este repositório contém uma infraestrutura local baseada em Docker Compose para hospedar vários serviços de apoio e aplicações web em um ambiente de laboratório.

## Visão geral

A estrutura foi organizada em pastas separadas por serviço, cada uma com seu próprio arquivo de compose. Todos os containers compartilham a mesma rede Docker externa chamada `infra-network` e utilizam o Traefik como proxy reverso para expor os serviços por hosts locais.

## Serviços incluídos

- Traefik: proxy reverso e dashboard
- WordPress + MySQL
- Mautic + MariaDB
- n8n + PostgreSQL
- Redis
- MinIO
- Portainer
- Adminer
- pgAdmin
- Mailhog
- Evolution API + PostgreSQL

## Estrutura do projeto

```text
/mnt/d/docker
├── create-lab.sh
├── hosts-lab.txt
├── scripts/
│   ├── start-all.sh
│   └── stop-all.sh
├── traefik/
├── wordpress/
├── wordpress-db/
├── mautic/
├── mautic-db/
├── n8n/
├── n8n-db/
├── redis/
├── minio/
├── portainer/
├── adminer/
├── pgadmin/
├── mailhog/
└── evolution-api/
```

## Como criar o ambiente

Execute o script principal:

```bash
cd /mnt/d/docker
./create-lab.sh
```

Durante a execução, o script irá perguntar quais serviços deseja criar. Você pode:

- digitar `A` para criar todos os serviços
- ou informar os serviços desejados separados por espaço

Exemplos:

```bash
A
```

ou

```bash
traefik wordpress evolution-api
```

O script também inclui automaticamente as dependências necessárias.

## Como iniciar tudo

```bash
cd /mnt/d/docker/scripts
./start-all.sh
```

## Como parar tudo

```bash
cd /mnt/d/docker/scripts
./stop-all.sh
```

## Hosts locais

Os serviços expostos pelo Traefik podem ser acessados pelos hosts abaixo, dependendo do que foi criado:

```text
127.0.0.1 traefik.lab.local
127.0.0.1 wordpress.lab.local
127.0.0.1 mautic.lab.local
127.0.0.1 n8n.lab.local
127.0.0.1 minio.lab.local
127.0.0.1 portainer.lab.local
127.0.0.1 adminer.lab.local
127.0.0.1 pgadmin.lab.local
127.0.0.1 mailhog.lab.local
127.0.0.1 evolution-api.lab.local
```

Para que esses hosts funcionem corretamente, adicione as entradas acima ao arquivo de hosts do sistema.

## Acesso aos serviços

- Dashboard do Traefik: http://traefik.lab.local
- WordPress: http://wordpress.lab.local
- Mautic: http://mautic.lab.local
- n8n: http://n8n.lab.local
- MinIO Console: http://minio.lab.local
- Portainer: http://portainer.lab.local
- Adminer: http://adminer.lab.local
- pgAdmin: http://pgadmin.lab.local
- Mailhog: http://mailhog.lab.local
- Evolution API: http://evolution-api.lab.local

## Observações

- Alguns serviços utilizam dependências de banco de dados e cache, como PostgreSQL, MySQL/MariaDB e Redis.
- O Evolution API foi configurado com PostgreSQL e Redis para funcionamento básico.
- Os dados persistentes ficam em diretórios dentro de `data/`.

## Comandos úteis

```bash
# Ver containers em execução
docker ps

# Ver logs de um container
docker logs <nome-do-container>

# Parar um serviço específico
docker compose down
```

## Notas de segurança

As credenciais e senhas utilizadas neste ambiente são apenas para laboratório. Para uso real, substitua-os por valores seguros.

## Evolution API + N8N
# n8n-nodes-evolution-api
## Excluir image dos Containers
# docker image prune -a
## Para remover também containers parados e volumes órfãos, rode primeiro:
# docker container prune
# docker volume prune
# docker image prune -a