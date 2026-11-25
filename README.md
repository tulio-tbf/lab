# Docker Lab

**Criado por:** Tulio Brançam de Freitas

- **E-mail:** [tulio@tbfconsultoria.com.br](mailto:tulio@tbfconsultoria.com.br)
- **Website:** [tbfconsultoria.com.br](https://tbfconsultoria.com.br)

Docker Lab cria um ambiente local de desenvolvimento com serviços web,
aplicações de automação, bancos de dados e ferramentas de IA em macOS,
Windows (WSL 2 ou Git Bash) e Linux.

O projeto foi pensado para uso em desenvolvimento, testes e prototipagem:
cada máquina pode montar seu próprio lab, a configuração é reproduzível por
scripts e os dados podem ser mantidos entre recriações de containers.

## Quando usar

Use o lab para:

- hospedar WordPress, Mautic, n8n, Evolution API e ferramentas administrativas;
- desenvolver integrações entre aplicações em uma rede Docker compartilhada;
- testar LLMs locais, RAG e agentes com Ollama, Qdrant, Open WebUI e SearXNG;
- trabalhar com bancos e interfaces de administração sem instalar cada produto
  diretamente no sistema;
- montar o mesmo ambiente em um Mac, em um PC Windows/WSL ou em Linux.

Este é um laboratório local, não um modelo de implantação de produção. As
credenciais e configurações padrão são simples e não devem ser expostas à
internet.

## Como funciona

A estrutura de cada serviço é gerada em um diretório-base, por padrão
`~/docker-shared`. O instalador cria:

- um diretório e um arquivo `docker-compose.yml` para cada serviço escolhido;
- a rede externa compartilhada `infra-network`;
- scripts de inicialização, parada, atualização e manutenção;
- o arquivo `lab.env`, que registra os diretórios e o domínio;
- uma lista `hosts-lab.txt` com os nomes locais dos serviços existentes.

Por padrão:

| Finalidade | Caminho padrão | Opção |
|---|---|---|
| Configuração, Compose e scripts | `~/docker-shared` | `-b`, `--base` |
| Dados persistentes das aplicações | `~/lab-data` | `-d`, `--data` |
| Backups | `~/backups` | `-o`, `--backups` |
| Domínio dos serviços web | `lab.test` | `-D`, `--domain` |

Todos os containers que precisam resolver outros containers usam a rede
`infra-network`. Os serviços web também recebem labels do Traefik e são
publicados em `http://<servico>.<dominio>`.

## Container Engine Support

**Docker é o padrão** e continua usando `docker compose`. Instalações antigas
sem `LAB_ENGINE` são tratadas como Docker.

```bash
./install.sh --engine docker
```

**Podman rootless em Linux** é o alvo do MVP. A execução integrada ainda precisa
ser confirmada em Linux nativo. WSL, Podman Machine no macOS e Windows nativo
estão fora do escopo deste MVP.

```bash
systemctl --user enable --now podman.socket
./install.sh --engine podman --base "$HOME/podman-lab" \
  --data "$HOME/podman-lab-data" --backups "$HOME/podman-lab-backups" \
  --services "wordpress n8n"
"$HOME/podman-lab/scripts/update-hosts.sh"
"$HOME/podman-lab/scripts/start-all.sh"
```

Use Podman 5.x, o provider `podman-compose` 1.5 ou superior, Netavark com
Aardvark DNS, `curl` e um usuário com mapeamentos em `/etc/subuid` e
`/etc/subgid`. Verifique `podman info` e
`PODMAN_COMPOSE_PROVIDER=podman-compose podman compose version`.
O instalador grava a escolha em `lab.env`. Os scripts consultam esse arquivo
e usam o engine da instalação.

Com Podman, acesse os serviços em `http://<serviço>.<domínio>:8000`. A opção
`--http-port` escolhe a porta na instalação. O Portainer fica desabilitado
nesse modo. Para administrar os serviços use os scripts do Lab, `podman ps`
e `podman logs`.

Instalações Docker e Podman usam bases, diretórios de dados e volumes
independentes. Uma migração entre engines requer backup, nova instalação e
restauração manual.

- [Orientação de escolha da engine](ESCOLHA-DA-ENGINE.md)
- [Guia de administração do Podman](GUIA-PODMAN.md)
- [Guia de administração do Docker](GUIA-DOCKER.md)

## Plataforma suportada

| Plataforma | Docker recomendado | Observações |
|---|---|---|
| macOS Intel ou Apple Silicon | Docker Desktop | Bash 3.2 já é suficiente; o Ollama nativo é recomendado |
| Windows com WSL 2 | Docker Engine no WSL ou Docker Desktop integrado | Projetos e dados devem ficar no sistema de arquivos Linux |
| Windows com Git Bash | Docker Desktop | Caminhos Windows podem ser fornecidos ao instalador |
| Linux | Docker Engine + Docker Compose v2 | Não exige Docker Desktop |

Pré-requisitos para o caminho Docker:

- Docker em execução;
- Docker Compose v2 (`docker compose`);
- Git;
- Bash;
- `sudo` para atualizar o arquivo de hosts.

No macOS, instale o Docker Desktop e as ferramentas de linha de comando:

```bash
xcode-select --install
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

No Windows, instale o WSL 2 e uma distribuição Ubuntu:

```powershell
wsl --install -d Ubuntu
```

Dentro do WSL:

```bash
sudo apt update
sudo apt install git openssh-client
ssh-add ~/.ssh/id_ed25519
```

Mantenha os projetos em `~/projects`, não em `/mnt/c` ou `/mnt/d`. Caminhos
Windows em disco externo podem ser usados para dados pelo instalador, mas
projetos e arquivos compartilhados com containers ficam mais confiáveis no
sistema de arquivos Linux.

Ao usar Docker Engine nativo no WSL, habilite `systemd`:

```ini
# /etc/wsl.conf
[boot]
systemd=true

[network]
generateResolvConf=false
```

Depois reinicie o WSL no PowerShell com `wsl --shutdown` e confirme:

```bash
sudo systemctl start docker
docker info
```

O Docker Desktop e o Docker Engine nativo do WSL são daemons separados. Eles
não compartilham automaticamente imagens, containers nem volumes.

## Serviços disponíveis

| Serviço | Uso | Dependências |
|---|---|---|
| Traefik | Proxy reverso e acesso por nomes locais | Nenhuma |
| WordPress | CMS e site PHP | Traefik + MySQL |
| MySQL do WordPress | Banco do WordPress | Nenhuma |
| Mautic | Automação de marketing | Traefik + MariaDB |
| MariaDB do Mautic | Banco do Mautic | Nenhuma |
| n8n | Automação de fluxos e integrações | Traefik |
| Redis | Cache e fila | Nenhuma |
| MinIO | Armazenamento compatível com S3 | Traefik |
| Portainer | Administração visual do Docker | Traefik |
| Adminer | Administração leve de bancos | Traefik |
| pgAdmin | Administração visual do PostgreSQL | Traefik |
| MailHog/Mailpit | Captura local de e-mails SMTP | Nenhuma |
| Evolution API | API WhatsApp | Traefik + PostgreSQL + Redis |
| Ollama | Modelos de linguagem locais | Nenhuma |
| Qdrant | Banco vetorial para RAG e memória | Traefik |
| Open WebUI | Interface web de chat para Ollama | Traefik + Ollama |
| SearXNG | Busca web para agentes e aplicações | Traefik |

Os bancos nomeados como `*-db` ficam fora do menu principal. Ao selecionar
WordPress, Mautic ou Evolution API, seus bancos e dependências são incluídos
automaticamente.

## Instalação rápida

Na raiz do repositório:

```bash
git clone <URL-DO-REPOSITORIO> lab
cd lab
chmod +x create-lab.sh
./create-lab.sh
```

Na primeira execução:

1. o script valida Docker e hardware;
2. o menu pergunta quais serviços criar;
3. as dependências necessárias são adicionadas;
4. os diretórios e arquivos Compose são gerados;
5. a rede `infra-network` é criada;
6. o script mostra os caminhos e os próximos comandos.

Seleção interativa:

```text
A                 todos os serviços
IA                Ollama, Qdrant, Open WebUI e SearXNG
n8n qdrant        nomes separados por espaço
traefik wordpress evolution-api
1 2 5             números exibidos no menu
1-4               intervalo
```

O último exemplo usa os nomes exibidos pelo menu; para Evolution API use
`evolution-api`.

Para executar sem menu:

```bash
./create-lab.sh --services "n8n qdrant"
./create-lab.sh --services "IA"
./create-lab.sh --services "traefik wordpress evolution-api"
```

Os nomes também podem ser combinados com `A` ou `IA`, conforme o parser do
script aceita:

```bash
./create-lab.sh --services "IA redis"
```

## Opções do instalador

```text
-b, --base DIRETÓRIO
    Diretório das configurações geradas.
    Padrão: ~/docker-shared

-d, --data DIRETÓRIO
    Diretório dos dados persistentes.
    Padrão: ~/lab-data

-o, --backups DIRETÓRIO
    Diretório dos backups gerados pela manutenção.
    Padrão: ~/backups

-D, --domain DOMÍNIO
    Domínio local dos serviços web.
    Padrão: lab.test

--ollama-mode MODO
    auto, native, docker, docker-gpu ou remote

--ollama-url URL
    Endereço exigido no modo remote.
    Exemplo: http://192.168.0.20:11434

--check-hardware
    Exibe diagnóstico de hardware e sai, sem gerar o lab.

--services LISTA
    Seleciona serviços sem abrir o menu.

-h, --help
    Exibe a ajuda do instalador.
```

Exemplos:

```bash
./create-lab.sh --base ~/docker-shared \
  --data ~/lab-data \
  --backups ~/backups \
  --domain lab.test

./create-lab.sh --base /opt/docker-lab \
  --data /srv/docker-lab-data \
  --backups /srv/docker-lab-backups

./create-lab.sh --ollama-mode docker-gpu --services IA
./create-lab.sh --ollama-mode remote \
  --ollama-url http://192.168.0.20:11434 \
  --services IA
./create-lab.sh --check-hardware
```

No WSL ou Git Bash, caminhos Windows também são aceitos quando há conversão
disponível:

```bash
./create-lab.sh --base 'D:\docker-shared' --data 'D:\lab-data'
```

As opções podem ser fornecidas por variáveis de ambiente:

```bash
LAB_BASE=/opt/docker-lab
LAB_DATA=/srv/docker-lab-data
LAB_BACKUPS=/srv/docker-lab-backups
LAB_DOMAIN=lab.test
LAB_OLLAMA_MODE=auto
LAB_OLLAMA_URL=
LAB_LLM_MODEL=qwen3:8b
```

Uso:

```bash
LAB_BASE=/opt/docker-lab \
LAB_DATA=/srv/docker-lab-data \
LAB_BACKUPS=/srv/docker-lab-backups \
LAB_LLM_MODEL=qwen3:8b \
./create-lab.sh --services IA
```

Argumentos de linha de comando têm precedência sobre as variáveis de ambiente.

## Diagnóstico e Ollama

Antes de criar serviços de IA, o instalador detecta:

- plataforma e versão do Docker;
- CPU, AVX2 e quantidade de RAM;
- memória reservada ao Docker;
- GPU NVIDIA visível ao Docker;
- VRAM disponível;
- disco livre;
- memória aproximada dos serviços escolhidos.

Ele então recomenda o modo do Ollama e um modelo que cabe no orçamento
calculado:

| Condição | Modo recomendado |
|---|---|
| macOS Apple Silicon | `native`, usando Metal |
| macOS Intel | `native`, evitando dividir RAM com a VM do Docker |
| GPU NVIDIA acessível pelo Docker | `docker-gpu` |
| GPU NVIDIA no sistema, mas não no Docker | `native` |
| Sem GPU NVIDIA | `docker`, com CPU |
| Ollama em outra máquina | `remote` |

Os modos têm estes significados:

- `auto`: escolhe o modo recomendado pelo hardware;
- `native`: Ollama instalado no sistema operacional;
- `docker`: Ollama em container usando CPU;
- `docker-gpu`: Ollama em container usando GPU NVIDIA;
- `remote`: os containers usam um Ollama acessível pela rede.

Modelo padrão via variável:

```bash
LAB_LLM_MODEL=qwen3:8b ./create-lab.sh --services IA
```

Depois da criação:

```bash
~/docker-shared/ollama/pull-models.sh
~/docker-shared/ollama/pull-models.sh qwen3:8b
```

No modo Ollama containerizado, os modelos persistem em
`~/lab-data/ollama`. No Ollama nativo, eles permanecem no sistema. Para usar
uma máquina remota:

```bash
# Na máquina que servirá o Ollama
OLLAMA_HOST=0.0.0.0:11434 ollama serve

# Na máquina que cria o lab
./create-lab.sh --ollama-mode remote \
  --ollama-url http://192.168.0.20:11434 \
  --services IA
```

Por segurança, libere a porta `11434` apenas na rede local e proteja o firewall.
Pendrives não aceleram modelos maiores. A RAM ou VRAM é mais importante que o
armazenamento externo; um SSD pode guardar os arquivos para liberar espaço
interno.

## Endereços locais

Depois de atualizar `/etc/hosts`, os serviços principais ficam disponíveis em:

| Serviço | URL |
|---|---|
| Traefik | `http://traefik.lab.test` |
| WordPress | `http://wordpress.lab.test` |
| Mautic | `http://mautic.lab.test` |
| n8n | `http://n8n.lab.test` |
| Redis | `redis:6379` dentro da rede Docker |
| MailHog/Mailpit | `http://mailhog.lab.test` |
| Evolution API | `http://evolution-api.lab.test` |
| Ollama | `http://ollama:11434` dentro da rede, no modo container |
| Qdrant | `http://qdrant.lab.test/dashboard` |
| Open WebUI | `http://open-webui.lab.test` |
| SearXNG | `http://searxng.lab.test` |
| Portainer | `http://portainer.lab.test` |
| Adminer | `http://adminer.lab.test` |
| pgAdmin | `http://pgadmin.lab.test` |
| MinIO | `http://minio.lab.test` |

Dentro da rede Docker, os serviços podem usar os nomes dos containers:

```text
http://qdrant:6333
http://searxng:8080/search?q=termo&format=json
http://ollama:11434
redis:6379
mailhog:1025
```

## Hosts locais

O instalador gera `~/docker-shared/hosts-lab.txt` com os serviços existentes.
Para aplicar o bloco gerenciado ao sistema:

```bash
~/docker-shared/scripts/update-hosts.sh
```

Opções geradas:

```text
--local-only, --wsl-only
    Atualiza somente /etc/hosts no macOS, Linux ou WSL

--windows-only
    Atualiza somente o arquivo Hosts do Windows a partir do WSL

-h, --help
    Exibe a ajuda
```

Exemplos no WSL:

```bash
~/docker-shared/scripts/update-hosts.sh --local-only
~/docker-shared/scripts/update-hosts.sh --windows-only
```

O script preserva o restante do arquivo Hosts e atualiza apenas o bloco marcado
do Docker Lab. No macOS, Linux e WSL ele solicita `sudo`; no Windows solicita
elevação do UAC.

## Iniciar e parar

Scripts gerados em `BASE/scripts`:

```bash
~/docker-shared/scripts/start-all.sh
~/docker-shared/scripts/stop-all.sh
~/docker-shared/scripts/start-custom.sh
~/docker-shared/scripts/update-lab.sh
~/docker-shared/scripts/update-hosts.sh
```

Iniciar todos os serviços criados:

```bash
~/docker-shared/scripts/start-all.sh
```

Parar todos os containers e redes locais dos serviços:

```bash
~/docker-shared/scripts/stop-all.sh
```

Parar não apaga dados nem volumes. `docker compose down` remove containers e
objetos Compose, mas não remove volumes nomeados.

Iniciar somente serviços selecionados e suas dependências:

```bash
~/docker-shared/scripts/start-custom.sh
```

O menu marca com `*` os serviços em execução e aceita nomes, números,
intervalos, `A` e `IA`.

Para outro diretório-base:

```bash
LAB_BASE=/opt/docker-lab /opt/docker-lab/scripts/start-all.sh
/opt/docker-lab/scripts/start-custom.sh --base /opt/docker-lab
/opt/docker-lab/scripts/stop-all.sh --base /opt/docker-lab
```

## Atualizar, adicionar, remover e limpar

O script de manutenção usa ações diretas ou um menu:

```bash
~/docker-shared/scripts/update-lab.sh
~/docker-shared/scripts/update-lab.sh atualizar
~/docker-shared/scripts/update-lab.sh adicionar
~/docker-shared/scripts/update-lab.sh remover
~/docker-shared/scripts/update-lab.sh limpar
```

Também são aceitas ações em inglês: `update`, `add`, `remove` e `clean`.

### Atualizar

`atualizar` executa o `pull` ou reconstrói as imagens dos serviços escolhidos
e recria somente os containers que estavam em execução.

Para bancos vinculados a uma aplicação:

- cria dump MySQL ou MariaDB;
- cria dump PostgreSQL;
- faz backup do estado SQLite usado por n8n e Open WebUI;
- cancela toda a atualização se qualquer backup falhar.

O Ollama nativo informa que deve ser atualizado pelo próprio sistema. O Ollama
containerizado é atualizado por imagem.

### Adicionar

`adicionar` lista apenas serviços ainda não criados e chama o instalador sem
alterar os demais. Depois pergunta se os novos serviços devem iniciar agora.

### Remover

`remover` oferece três níveis:

1. só o container;
2. container, imagem e configuração, mantendo dados e volumes;
3. tudo, inclusive dados e volumes.

O nível 3 exige confirmação digitada e cria backup antes da exclusão. Na
remoção, bancos associados são tratados junto com a aplicação. O script avisa
quando um serviço restante depende do serviço removido.

O Ollama nativo não é instalado nem removido pelo Docker. Seus modelos podem
ser mantidos no sistema depois da remoção dos arquivos Docker do lab.

### Limpar

`limpar` remove:

- imagens sem referência;
- cache de build;
- modelos Ollama escolhidos pelo usuário, se o Ollama estiver acessível.

Volumes e imagens de serviços parados não são removidos por essa ação.

## Backups

A criação das configurações não agenda backups automáticos. O diretório
`BACKUPS` é usado pelas ações `atualizar` e `remover`, no nível destrutivo.

A manutenção usa:

```text
~/backups/databases/<data-hora>/<servico>.sql.gz
~/backups/volumes/<data-hora>/<nome>.tar.gz
~/backups/volumes/<data-hora>/RESTAURAR.txt
```

Antes de atualizar:

- bancos envolvidos recebem dump;
- SQLite do n8n recebe backup;
- SQLite do Open WebUI recebe backup.

Antes da remoção completa:

- bancos recebem dump;
- dados configurados recebem arquivos compactados;
- volumes Docker recebem arquivos compactados;
- Compose e configurações recebem arquivos compactados.

O script mostra o caminho dos backups e gera comandos de restauração em
`RESTAURAR.txt`.

Reexecutar `create-lab.sh` não é uma operação de remoção: ele recria ou
atualiza as configurações dos serviços selecionados e mantém dados existentes.
Para atualizar imagens, use `update-lab.sh atualizar`.

## Persistência

Três caminhos têm funções diferentes:

| Local | Conteúdo | Removido por |
|---|---|---|
| `BASE` | Compose, scripts, certificados e configurações | remoção completa do serviço |
| `DATA` | Bind mounts e dados das aplicações | remoção completa |
| `BACKUPS` | Arquivos gerados pela manutenção | nunca pela criação |

Volumes Docker nomeados utilizados pelo lab:

```text
wordpress-db-data
mautic-db-data
mautic-config-data
mautic-media-files-data
mautic-media-images-data
mautic-logs-data
evolution-db-data
pgadmin-data
```

Dados importantes que ficam em `DATA`:

```text
~/lab-data/wordpress
~/lab-data/n8n
~/lab-data/redis
~/lab-data/minio
~/lab-data/portainer
~/lab-data/pgadmin
~/lab-data/evolution-api
~/lab-data/ollama
~/lab-data/qdrant
~/lab-data/open-webui
```

Não sincronize `lab-data`, volumes Docker ou backups em Dropbox, OneDrive,
iCloud ou pendrives formatados como sistemas comuns. Arquivos SQLite e bancos
podem ficar inconsistentes durante sincronização. Para migrar dados entre
máquinas, use dumps ou backups do script.

### Migração entre máquinas

Configurações e o repositório podem ser sincronizados por Git. Bases de dados,
volumes e arquivos gerados não devem.

Em cada máquina:

1. execute `create-lab.sh` com os mesmos diretórios e domínio;
2. importe os dumps de banco;
3. restaure os arquivos de `DATA`;
4. restaure os volumes Docker necessários;
5. execute `start-custom.sh` ou `start-all.sh`;
6. atualize os hosts locais.

## Comandos úteis

Listar containers:

```bash
docker ps
docker ps -a
```

Ver consumo:

```bash
docker stats
docker system df
docker system df -v
```

Gerenciar um serviço pelo Compose:

```bash
cd ~/docker-shared/<servico>
docker compose ps
docker compose logs -f --tail=200
docker compose config
docker compose up -d --build
docker compose restart
docker compose stop
docker compose start
docker compose down
```

Nunca use `docker compose down -v` sem ter certeza de que pode apagar todos
os volumes associados ao Compose.

Abrir um shell:

```bash
docker exec -it traefik sh
docker exec -it wordpress sh
docker exec -it wordpress-db sh
docker exec -it mautic sh
docker exec -it mautic-db sh
docker exec -it n8n sh
docker exec -it redis sh
docker exec -it evolution-api sh
docker exec -it evolution-db sh
docker exec -it ollama sh
docker exec -it qdrant sh
docker exec -it searxng sh
```

Algumas imagens não incluem `sh`; use `docker logs` ou a interface web nesses
casos.

Inspecionar:

```bash
docker inspect <container>
docker logs --tail=200 <container>
docker logs -f <container>
docker port <container>
docker top <container>
docker diff <container>
docker network inspect infra-network
```

## Git por SSH nos containers

WordPress, Mautic, n8n e Evolution API recebem o socket do `ssh-agent` do host.
A chave privada não é copiada para o container.

No macOS:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

No Linux/WSL:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
ssh-add -l
```

Recrie os containers após carregar o agente:

```bash
for service in wordpress mautic n8n evolution-api; do
  if [[ -f "$HOME/docker-shared/$service/docker-compose.yml" ]]; then
    (cd "$HOME/docker-shared/$service" && docker compose up -d --build --force-recreate)
  fi
done
```

O socket dá ao container somente a capacidade de solicitar operações com as
identidades já carregadas no agente. Encaminhe-o apenas para containers
confiáveis.

## Credenciais de laboratório

Estas são credenciais padrão destinadas ao ambiente local:

| Serviço | Usuário/chave | Senha ou chave |
|---|---|---|
| WordPress/MySQL | `wordpress` | `wordpress123` |
| MySQL administrador | `root` | `root123` |
| Mautic/MariaDB | `mautic` | `mautic123` |
| MariaDB administrador | `root` | `root123` |
| Evolution API | `AUTHENTICATION_API_KEY` | `change-me` |
| Evolution/PostgreSQL | `postgres` | `postgres123` |
| pgAdmin | `admin@example.com` | `admin123` |
| MinIO | `admin` | `admin123` |

Redis não tem autenticação no Compose padrão. Traefik, Adminer e MailHog não
têm senha própria configurada.

Altere todas as credenciais antes de qualquer uso além da rede local. A
senha do MySQL do WordPress também é armazenada em
`~/lab-data/wordpress/secrets/db_password`.

## Segurança e operação

- não exponha o Traefik ou portas administrativas na internet;
- não reutilize as credenciais padrão em ambientes compartilhados;
- proteja a porta do Ollama remoto por firewall;
- faça backup antes de atualizar versões maiores de bancos;
- revise `docker-compose.yml` antes de executar integrações;
- mantenha os dados fora de sincronizadores de nuvem;
- revise portas publicadas por Compose e remova as desnecessárias.

## Solução de problemas

### Docker não está acessível

```bash
docker info
docker compose version
```

Confirme se o Docker Desktop está aberto ou se o daemon foi iniciado no WSL:

```bash
sudo systemctl start docker
```

### Serviço não abre pelo nome local

```bash
cat ~/docker-shared/hosts-lab.txt
~/docker-shared/scripts/update-hosts.sh
docker network inspect infra-network
docker ps
```

No macOS também pode ser necessário limpar o cache de DNS.

### Container reinicia ou não fica saudável

```bash
docker compose -f ~/docker-shared/<servico>/docker-compose.yml logs --tail=200
docker inspect <container>
```

### Erro de porta ocupada

Identifique o processo que usa a porta:

```bash
# Linux/macOS
lsof -nP -iTCP:80 -sTCP:LISTEN

# WSL/Windows
netstat -ano | findstr :80
```

Interrompa o processo ou altere a publicação no `docker-compose.yml`.

### MinIO não inicia

O Compose atual referencia `minio/minio`, que pode não estar disponível. O
lab mantém o diretório e os dados, mas não inicia o MinIO automaticamente.
Escolha uma imagem mantida e compatível antes de alterar o Compose.

### Ollama não responde dos containers

- modo `docker`/`docker-gpu`: confirme que o container `ollama` está
  em execução;
- modo `native`: confirme que o Ollama está acessível no host;
- modo `remote`: confirme `OLLAMA_HOST=0.0.0.0:11434`, firewall e URL.

## Recriar o ambiente

Reexecutar o instalador não exige apagar os dados. Ele sobrescreve as
configurações dos serviços selecionados e usa os volumes ou diretórios
existentes.

Para atualizar imagens e bancos com backups:

```bash
~/docker-shared/scripts/update-lab.sh atualizar
```

Para adicionar um serviço novo:

```bash
~/docker-shared/scripts/update-lab.sh adicionar
```

Para escolher como remover um serviço:

```bash
~/docker-shared/scripts/update-lab.sh remover
```
