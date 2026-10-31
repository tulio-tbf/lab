# Docker Lab

Infraestrutura local baseada em Docker Compose para hospedar serviços de apoio
e aplicações web em macOS, Windows (WSL 2 ou Git Bash) e Linux. O mesmo
repositório e os mesmos comandos funcionam nas duas máquinas do ambiente
híbrido (MacBook + Windows/WSL).

Cada serviço possui seu próprio arquivo Compose. Todos compartilham a rede
externa `infra-network` e os serviços web são publicados pelo Traefik.

## Requisitos

- **macOS:** Docker Desktop, Git e o Bash nativo do sistema (3.2 já basta);
- **Windows:** WSL 2 (Ubuntu) com Docker Engine nativo ou Docker Desktop com
  integração WSL;
- **Linux:** Docker Engine + Docker Compose v2.

### Instalação no macOS

1. Instale o [Docker Desktop para Mac](https://www.docker.com/products/docker-desktop/)
   escolhendo a versão do seu processador (Intel ou Apple Silicon). Em
   *Settings > Resources*, reserve pelo menos 4 GB de memória para o lab
   completo.
2. Instale as ferramentas de linha de comando: `xcode-select --install`
   (inclui o Git). O Homebrew é opcional.
3. Carregue a chave SSH no agente para que os containers usem Git por SSH:

   ```bash
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

   O Docker Desktop repassa esse agente aos containers por
   `/run/host-services/ssh-auth.sock`; o instalador já gera os Compose com
   esse caminho no macOS.

### Instalação no Windows

1. Instale o WSL 2 com Ubuntu (`wsl --install -d Ubuntu` no PowerShell).
2. Instale **um** Docker: o Engine nativo dentro do WSL (instruções abaixo) ou
   o Docker Desktop com a distribuição habilitada em
   *Settings > Resources > WSL Integration*. Os dois não compartilham imagens
   nem volumes.
3. Dentro do WSL: `sudo apt install git openssh-client` e configure a chave
   SSH no agente com `ssh-add`.
4. Use o VS Code com a extensão **WSL** e mantenha os projetos no sistema de
   arquivos do Linux (`~/projects`), não em `/mnt/c` ou `/mnt/d`: o acesso a
   discos do Windows é muito mais lento e causa problemas de permissão.

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

## Ambiente híbrido (Mac + Windows)

- O Git é a fonte da verdade: clone este repositório e os projetos em
  `~/projects` nas duas máquinas e sincronize por `git pull`/`git push`.
- Configurações geradas (`~/docker-shared`), dados (`~/lab-data`) e volumes
  Docker são locais de cada máquina. Para levar dados de uma para a outra, use
  dumps em `~/backups`; nunca sincronize essas pastas com Dropbox, OneDrive ou
  iCloud, pois isso corrompe os bancos.
- Execute `./create-lab.sh` em cada máquina. O script detecta macOS, WSL,
  Linux ou Git Bash e ajusta o agente SSH, o arquivo de hosts e as mensagens.
- O `.gitattributes` força LF nos scripts `.sh`, evitando erros de `\r` quando
  o repositório é clonado pelo lado Windows.

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
- Mailhog (servido pela imagem Mailpit, com o mesmo nome e as mesmas portas)
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

O domínio local padrão é `lab.test`. Ele pode ser alterado com `--domain` ou
`LAB_DOMAIN`. Evite `.local`: no macOS esse sufixo é resolvido pelo mDNS
(Bonjour) e as requisições podem demorar segundos.

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
serviços selecionados. Para atualizar o `/etc/hosts` (e, no WSL, também o
arquivo do Windows), execute o script gerado:

```bash
~/docker-shared/scripts/update-hosts.sh
```

O script atualiza um bloco gerenciado e pode ser executado novamente quando a
lista de serviços mudar. No macOS, Linux e WSL ele pede `sudo` (no macOS
também limpa o cache de DNS); para o arquivo do Windows, abre uma solicitação
de elevação do UAC. Os demais conteúdos dos arquivos `hosts` são preservados.
Para atualizar somente um deles a partir do WSL:

```bash
~/docker-shared/scripts/update-hosts.sh --local-only
~/docker-shared/scripts/update-hosts.sh --windows-only
```

Endereços disponíveis incluem:

- http://traefik.lab.test
- http://wordpress.lab.test
- http://mautic.lab.test
- http://n8n.lab.test
- http://minio.lab.test
- http://portainer.lab.test
- http://adminer.lab.test
- http://pgadmin.lab.test
- http://mailhog.lab.test
- http://evolution-api.lab.test

## Migrar uma instalação existente de `lab.local`

Quem já usava o lab com `*.lab.local` pode manter esse domínio gerando com
`./create-lab.sh --domain lab.local`. Para migrar para `lab.test`, gere o lab
novamente, execute `update-hosts.sh` e atualize as URLs gravadas nos bancos:

```bash
docker exec wordpress wp --allow-root search-replace \
  'http://wordpress.lab.local' 'http://wordpress.lab.test' --all-tables
```

No Mautic, ajuste a *Site URL* em *Configurações > Configurações do sistema*.
O n8n e a Evolution API recebem a nova URL pelo Compose ao serem recriados.

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
