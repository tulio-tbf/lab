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
- n8n (dados em SQLite)
- Redis
- MinIO
- Portainer
- Adminer
- pgAdmin
- Mailhog (servido pela imagem Mailpit, com o mesmo nome e as mesmas portas)
- Evolution API + PostgreSQL
- Ollama (LLMs locais; em container ou nativo, conforme o hardware)
- Qdrant (banco vetorial para RAG e memória de agentes)
- Open WebUI (interface de chat para testar modelos e prompts)
- SearXNG (busca na web sem API key, usada como ferramenta pelos agentes)

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

## Serviços de IA

Informe `IA` na seleção para criar `ollama qdrant open-webui searxng` (o
Traefik entra como dependência). Antes de gerar os arquivos, o script faz um
diagnóstico de CPU, RAM, GPU, memória do Docker e disco, e então:

- escolhe onde o Ollama roda;
- recomenda o modelo que cabe na memória livre;
- informa quanta memória reservar ao Docker e pede confirmação se algo não
  couber.

Para ver só o diagnóstico, sem criar nada:

```bash
./create-lab.sh --check-hardware
```

| Máquina | Modo escolhido | Motivo |
|---|---|---|
| Mac (Intel ou Apple Silicon) | `native` | Containers não acessam a GPU no Mac; no Apple Silicon o Ollama nativo usa Metal, e no Intel evita dividir a RAM com a VM do Docker Desktop. |
| Windows/Linux com GPU NVIDIA visível ao Docker | `docker-gpu` | Container com aceleração. |
| Windows/Linux com GPU NVIDIA sem NVIDIA Container Toolkit | `native` | O Ollama nativo usa a GPU direto. |
| Windows/Linux sem GPU | `docker` | Só CPU; no Linux/WSL o container tem desempenho igual ao nativo. |

O modo pode ser forçado com `--ollama-mode native|docker|docker-gpu|remote`.
O modo `remote` usa o Ollama de outra máquina da rede, por exemplo o PC com
GPU servindo o Mac:

```bash
./create-lab.sh --ollama-mode remote --ollama-url http://192.168.0.20:11434
```

O endereço que os containers devem usar (credencial Ollama do n8n, Open
WebUI) e os modelos escolhidos ficam em `~/docker-shared/ollama/ollama.env`.
Depois de subir o lab, baixe os modelos com:

```bash
~/docker-shared/ollama/pull-models.sh            # modelo recomendado + nomic-embed-text
~/docker-shared/ollama/pull-models.sh qwen3:8b   # outro modelo
```

Os modelos indicados são da família Qwen 3, que suporta tool calling (necessário
para agentes). O padrão pode ser trocado com `LAB_LLM_MODEL`. Sem GPU, prefira
modelos de até 4B: os maiores funcionam, mas ficam lentos demais para fluxos de
agente.

Dentro da `infra-network`, os serviços ficam em `http://qdrant:6333` e
`http://searxng:8080/search?q=TERMO&format=json`.

### Pendrive e disco externo

Pendrive não acelera a IA. O modelo precisa caber na RAM (ou na VRAM): um
pendrive USB lê a centenas de MB/s, a RAM a dezenas de GB/s, então swap ou
"ReadyBoost" em pendrive deixa tudo mais lento. Um **SSD externo** serve só
para guardar modelos e liberar o disco interno: aponte `--data` para ele
(modo container) ou defina `OLLAMA_MODELS` (Ollama nativo).

## Iniciar e parar

Os scripts gerados descobrem o diretório base pela sua própria localização:

```bash
/opt/docker-lab/scripts/start-all.sh
/opt/docker-lab/scripts/stop-all.sh
```

Para subir só alguns serviços, use o `start-custom.sh`. Ele lista apenas os
serviços já criados, marca com `*` os que estão rodando e aceita os mesmos
formatos de escolha do instalador (`A`, `IA`, nomes, números ou intervalos).
As dependências sobem junto: escolher `wordpress` também inicia `wordpress-db` e `traefik`.

```bash
/opt/docker-lab/scripts/start-custom.sh
```

O diretório também pode ser sobrescrito:

```bash
LAB_BASE=/opt/docker-lab ./scripts/start-all.sh
./scripts/stop-all.sh --base /opt/docker-lab
```

## Manutenção: atualizar, adicionar, remover e limpar

O `update-lab.sh` reúne a manutenção do lab num menu, ou direto pela ação:

```bash
~/docker-shared/scripts/update-lab.sh             # menu
~/docker-shared/scripts/update-lab.sh atualizar
~/docker-shared/scripts/update-lab.sh adicionar
~/docker-shared/scripts/update-lab.sh remover
~/docker-shared/scripts/update-lab.sh limpar
```

- **Atualizar:** faz `pull` das imagens de registro e reconstrói as locais
  (wordpress, mautic, evolution-api) com a base mais recente. Só recria os
  containers que estavam rodando e cuja imagem mudou. Escolher uma aplicação
  inclui o banco dela.
- **Adicionar:** lista só os serviços que ainda não existem e chama o
  `create-lab.sh` sem mexer nos demais. Os hosts continuam com todos os
  serviços.
- **Remover:** três níveis: (1) só o container; (2) container, imagem e
  configuração, com os dados mantidos; (3) tudo, inclusive dados e volumes,
  com backup antes e confirmação digitada. O banco sai junto com a aplicação.
  Se outro serviço depender do removido, o script avisa antes.
- **Limpar:** apaga imagens antigas sem tag e o cache de build, mostra o
  espaço antes e depois e permite apagar modelos do Ollama.

### Backups automáticos

Antes de atualizar, e antes de remover no nível 3, o script salva:

- dump completo de cada banco envolvido em `~/backups/databases/<data-hora>/`;
- o SQLite do n8n e do Open WebUI, além de volumes, dados e configuração
  removidos, em `~/backups/volumes/<data-hora>/`.

Ao final, o script mostra as pastas e os arquivos criados. Cada pasta tem um
`RESTAURAR.txt` com os comandos de restauração. Se algum backup falhar, a
operação é cancelada antes de qualquer alteração.

> O n8n grava em SQLite (`~/lab-data/n8n/data/.n8n`), sem banco separado.

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
- http://qdrant.lab.test/dashboard
- http://open-webui.lab.test
- http://searxng.lab.test

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
