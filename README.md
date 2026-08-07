# Docker Lab

Infraestrutura local baseada em Docker Compose para hospedar serviços de apoio
e aplicações web em Windows (WSL 2 ou Git Bash) e Linux.

Cada serviço possui seu próprio arquivo Compose. Todos compartilham a rede
externa `infra-network` e os serviços web são publicados pelo Traefik.

## Requisitos

- Docker Engine + Docker Compose v2 no Linux; ou
- Docker Desktop com integração WSL 2 no Windows;
- Bash 4 ou superior.

No Windows, execute os comandos abaixo em uma distribuição WSL ou no Git Bash.
O script aceita tanto caminhos WSL (`/mnt/d/docker`) quanto caminhos Windows
(`D:\docker`) quando a ferramenta de conversão do ambiente está disponível.

## Serviços

- Traefik
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

## Criar o ambiente

Por padrão, os arquivos são criados em `./docker`, ao lado deste README, e os
dados persistentes em `./docker/data`:

```bash
./create-lab.sh
```

Para escolher os diretórios:

```bash
./create-lab.sh --base /opt/docker-lab --data /srv/docker-lab-data
```

Exemplo no Windows/WSL:

```bash
./create-lab.sh --base /mnt/d/docker --data /mnt/d/docker/data
```

Também é possível usar caminhos no formato Windows dentro do WSL ou Git Bash:

```bash
./create-lab.sh --base 'D:\docker' --data 'D:\docker\data'
```

As mesmas opções podem ser definidas por variáveis de ambiente. Argumentos de
linha de comando têm precedência:

```bash
LAB_BASE=/opt/docker-lab LAB_DATA=/srv/docker-lab-data ./create-lab.sh
```

Use `./create-lab.sh --help` para consultar as opções. Durante a execução,
informe `A` para todos os serviços ou uma lista separada por espaços, como:

```text
traefik wordpress evolution-api
```

As dependências necessárias são incluídas automaticamente.

## Iniciar e parar

Os scripts gerados descobrem o diretório base pela sua própria localização:

```bash
/opt/docker-lab/scripts/start-all.sh
/opt/docker-lab/scripts/stop-all.sh
```

O diretório também pode ser sobrescrito:

```bash
LAB_BASE=/opt/docker-lab ./script/start-all.sh
./script/stop-all.sh --base /opt/docker-lab
```

## Hosts locais

O instalador gera `hosts-lab.txt` no diretório base somente com os serviços
selecionados. Adicione seu conteúdo ao arquivo de hosts:

- Linux e WSL: `/etc/hosts`
- Windows: `C:\Windows\System32\drivers\etc\hosts`

Endereços disponíveis incluem:

- http://traefik.lab.local
- http://wordpress.lab.local
- http://mautic.lab.local
- http://n8n.lab.local
- http://minio.lab.local
- http://portainer.lab.local
- http://adminer.lab.local
- http://pgadmin.lab.local
- http://mailhog.lab.local
- http://evolution-api.lab.local

## Persistência e segurança

Todos os bind mounts passam a usar os diretórios escolhidos em `BASE` e
`DATA`; não há dependência fixa de `/mnt/d/docker`.

As credenciais presentes nos arquivos são adequadas somente para laboratório.
Troque senhas, chaves e demais segredos antes de expor qualquer serviço fora
de uma máquina de desenvolvimento.
