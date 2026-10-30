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

Ao usar Docker Engine nativo no WSL, habilite o `systemd` em `/etc/wsl.conf`:

```ini
[boot]
systemd=true

[network]
generateResolvConf=false
```

Depois de alterar esse arquivo, execute `wsl --shutdown` no PowerShell e
confirme no WSL com `sudo systemctl start docker`. O Docker Desktop usa outro
daemon e não compartilha automaticamente as imagens do Engine nativo.

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

Por padrão, as configurações são criadas em `~/docker-shared`, os dados
persistentes em `~/lab-data` e os diretórios de backup em `~/backups`:

```bash
./create-lab.sh
```

Para escolher os diretórios:

```bash
./create-lab.sh --base /opt/docker-lab --data /srv/docker-lab-data
```

O diretório de backups também pode ser definido:

```bash
./create-lab.sh --base ~/docker-shared --data ~/lab-data --backups ~/backups
```

Exemplo no Windows/WSL:

```bash
./create-lab.sh --base /mnt/d/docker-shared --data /mnt/d/lab-data --backups /mnt/d/backups
```

Também é possível usar caminhos no formato Windows dentro do WSL ou Git Bash:

```bash
./create-lab.sh --base 'D:\docker' --data 'D:\docker\data'
```

As mesmas opções podem ser definidas por variáveis de ambiente. Argumentos de
linha de comando têm precedência:

```bash
LAB_BASE=/opt/docker-lab LAB_DATA=/srv/docker-lab-data LAB_BACKUPS=/srv/backups ./create-lab.sh
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
LAB_BASE=/opt/docker-lab ./scripts/start-all.sh
./scripts/stop-all.sh --base /opt/docker-lab
```

## Hosts locais

O instalador gera `hosts-lab.txt` no diretório de configuração somente com os
serviços selecionados. Para atualizar os hosts do WSL e do Windows, execute o
script gerado:

```bash
~/docker-shared/scripts/update-hosts.sh
```

O script atualiza um bloco gerenciado e pode ser executado novamente quando a
lista de serviços mudar. No WSL, ele pede `sudo`; para o arquivo do Windows,
abre uma solicitação de elevação do UAC. Os demais conteúdos dos arquivos
`hosts` são preservados. Para atualizar somente um deles:

```bash
~/docker-shared/scripts/update-hosts.sh --wsl-only
~/docker-shared/scripts/update-hosts.sh --windows-only
```

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

As configurações geradas ficam em `BASE`, os arquivos das aplicações e demais
bind mounts ficam em `DATA`, e `BACKUPS` recebe as pastas `databases`, `volumes`
e `projects`. A criação dessas pastas não executa nem agenda backups.

WordPress, n8n, Redis, MinIO, Portainer e Evolution API usam bind mounts sob
`DATA`. Os bancos MySQL, MariaDB e PostgreSQL, o pgAdmin e os dados do Mautic
continuam usando volumes Docker nomeados para preservar as permissões Unix.
Esses volumes não são movidos para `DATA` nem copiados automaticamente para
`BACKUPS`.

As credenciais presentes nos arquivos são adequadas somente para laboratório.
Troque senhas, chaves e demais segredos antes de expor qualquer serviço fora
de uma máquina de desenvolvimento.
