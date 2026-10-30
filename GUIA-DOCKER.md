# Guia de administração do Docker Lab

Este guia considera que os comandos serão executados no WSL ou em um terminal
Linux e que as configurações do laboratório estão em `~/docker-shared`.

```bash
cd ~/docker-shared
```

> As credenciais incluídas neste laboratório são destinadas somente ao
> desenvolvimento local. Consulte os arquivos `docker-compose.yml` antes de
> executar comandos de banco de dados caso elas tenham sido alteradas.

> Este laboratório usa o Docker Engine selecionado pelo comando `docker`.
> No WSL com Engine nativo, confirme que o `systemd` está habilitado em
> `/etc/wsl.conf` e que `sudo systemctl start docker` funciona. O Docker
> Desktop não compartilha automaticamente as imagens desse Engine.

## Gerenciar todo o laboratório

Iniciar todos os serviços:

```bash
./scripts/start-all.sh
```

Parar e remover os containers e redes Compose:

```bash
./scripts/stop-all.sh
```

O script para os serviços em ordem inversa à inicialização e continua tentando
os demais se algum `docker compose down` falhar; ao final, lista as falhas.
Ele verifica se o Docker Engine está acessível antes de começar. A opção
`down` não remove os volumes nomeados dos bancos.

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

O script `start-all.sh` cria essa rede automaticamente quando ela ainda não
existe.

## Resultado dos testes (30/10/2026)

Foram encontrados 14 containers em execução na rede `infra-network`. Os
endpoints HTTP testados dos serviços disponíveis responderam, exceto o
WordPress, que retorna erro de banco. O MinIO não possui container criado
nesta instalação.

| Serviço | Resultado observado |
|---|---|
| Traefik | Dashboard/API respondendo (HTTP 200). |
| WordPress | HTTP 500, “Error establishing a database connection”. A conexão do PHP ao MySQL foi confirmada; o banco `wordpress` tem 0 tabelas. |
| Mautic | Página de instalação respondendo (HTTP 200); MariaDB disponível, banco `mautic` com 0 tabelas. |
| n8n | `/healthz` responde HTTP 200; versão 2.45.7. Banco SQLite íntegro, com 11 workflows, 4 credenciais e 1 usuário. Os workflows estavam inativos. |
| Redis | `PING` responde `PONG`. |
| MinIO | Não está em execução e não há container criado. |
| Portainer | API responde, versão 2.45.3; a inicialização do administrador expirou. |
| Adminer | Interface responde HTTP 200. |
| pgAdmin | Endpoint de verificação `/misc/ping` responde HTTP 200. |
| MailHog | Interface e API respondem HTTP 200; SMTP aceitou as mensagens de teste. |
| Evolution API | API responde HTTP 200, versão 2.3.7; `evolution-db` está saudável e tem 37 tabelas. |

O `start-all.sh` tenta iniciar os serviços configurados e informa falhas ao
final. O MinIO está temporariamente fora da lista de inicialização porque a
imagem `minio/minio` configurada não está disponível. O script informa que o
está ignorando e continua com os demais serviços; falhas em outros serviços
continuam sendo reportadas normalmente.

Os containers MySQL e MariaDB estão disponíveis, embora seus bancos
`wordpress` e `mautic` tenham 0 tabelas. Os dois PostgreSQL aceitam conexões;
`evolution-db` tem 37 tabelas e `n8n-db` tem 0. O container `n8n-db` está
ativo, mas não é usado pelo n8n desta instalação: o Compose não configura
`DB_TYPE=postgresdb` e o n8n usa o SQLite restaurado em
`~/lab-data/n8n/data/.n8n/database.sqlite`.

## Usuários e senhas padrão

Estas credenciais são somente para laboratório local. As credenciais abaixo
foram conferidas nas configurações geradas; a existência de uma conta de
aplicação depende de a instalação inicial ter sido concluída.

| Serviço | Usuário/chave | Senha | Estado/notas |
|---|---|---|---|
| Traefik | — | — | Dashboard sem autenticação; não exponha fora da máquina local. |
| WordPress | — | — | Nenhum usuário do site foi configurado. O banco está vazio e o site retorna erro. |
| MySQL do WordPress | `wordpress` | `wordpress123` | O segredo também está em `~/lab-data/wordpress/secrets/db_password`. Administrador: `root` / `root123`. |
| Mautic | — | — | Ainda na instalação inicial; crie o primeiro usuário no assistente. Use `dev@lab.local` como email. |
| MariaDB do Mautic | `mautic` | `mautic123` | Administrador: `root` / `root123`. |
| n8n | `admin@lab.local` | Senha existente, não definida pelo Compose | Conta restaurada do banco antigo; use a senha já cadastrada. |
| PostgreSQL `n8n-db` | `n8n` | `n8n123` | Credencial definida no Compose, mas este banco não é usado pelo n8n atual. |
| Redis | — | — | Sem autenticação configurada. |
| MinIO | `admin` | `admin123` | Valores ainda definidos no Compose; serviço desativado na inicialização até a escolha de uma imagem disponível. |
| Portainer | — | — | A inicialização do administrador expirou; não há senha padrão. Reinicie o container e conclua a criação do administrador em até 5 minutos. |
| Adminer | — | — | Sem conta própria; use as credenciais do banco selecionado. |
| pgAdmin | `admin@example.com` | `admin123` | Email/senha de bootstrap definidos no Compose. Para novas contas, o email padrão é `dev@lab.local`; mudar a variável do Compose não altera um usuário já gravado no volume. |
| MailHog | — | — | Sem autenticação. |
| Evolution API | API key: `change-me` | — | Chave definida no Compose; troque-a antes de qualquer exposição além do laboratório local. |
| PostgreSQL da Evolution API | `postgres` | `postgres123` | Banco `evolution`. |

As senhas de banco são valores de desenvolvimento e devem ser substituídas
antes de qualquer uso fora do computador local.

Para atualizar os domínios `*.lab.local` no WSL e no Windows, execute o
sincronizador gerado. Ele atualiza apenas o bloco gerenciado do Docker Lab,
pede `sudo` para o WSL e solicita elevação do UAC para o Windows:

```bash
~/docker-shared/scripts/update-hosts.sh
```

Também é possível atualizar apenas um dos arquivos:

```bash
~/docker-shared/scripts/update-hosts.sh --wsl-only
~/docker-shared/scripts/update-hosts.sh --windows-only
```

## Gerenciar um serviço

Substitua `<servico>` pelo diretório desejado, por exemplo `wordpress`,
`wordpress-db`, `evolution-api` ou `evolution-db`.

```bash
cd ~/docker-shared/<servico>
```

Criar ou iniciar:

```bash
docker compose up -d --build
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

Para serviços que usam diretamente uma imagem publicada, baixe a imagem e
recrie o container:

```bash
docker compose pull
docker compose up -d --force-recreate
```

WordPress, Mautic e Evolution API usam imagens locais construídas sobre as
imagens oficiais para incluir o cliente SSH; Git também está disponível nos
quatro containers, e o WordPress inclui WP-CLI. Ao iniciar esses serviços,
`--build` recompõe as imagens quando necessário. Para atualizar manualmente
uma imagem-base personalizada e recriar o container:

```bash
docker compose build --pull
docker compose up -d --force-recreate
```

Para atualizar o n8n, use o script abaixo. Ele só recria o container se o
download da imagem terminar com sucesso:

```bash
cd ~/docker-shared/n8n
./update.sh
```

Não execute apenas `docker compose up -d --force-recreate` depois de um
`docker compose pull` com erro, pois o Compose pode iniciar a imagem antiga
que já está armazenada localmente.

> Antes de atualizar imagens de banco de dados, faça backup e confira as notas
> de migração da versão. Não use `docker compose down -v` neste laboratório sem
> entender o impacto, pois essa opção remove volumes nomeados.

Os bancos usam os volumes Docker nomeados `wordpress-db-data`,
`mautic-db-data`, `n8n-db-data` e `evolution-db-data`. Isso evita problemas de
permissão dos bancos em diretórios Windows montados no WSL.
O pgAdmin também usa o volume nomeado `pgadmin-data` pelo mesmo motivo.

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

O container inclui Git e WP-CLI. Execute os comandos como `www-data` para
evitar criar arquivos pertencentes ao root no diretório do site:

```bash
docker exec wordpress git --version
docker exec --user www-data wordpress wp --info
docker exec --user www-data wordpress wp core version
```

`wp core version` requer que a instalação do WordPress já esteja disponível.
O `wp` também pode executar comandos administrativos, por exemplo:

```bash
docker exec --user www-data wordpress wp plugin list
docker exec --user www-data wordpress wp cache flush
```

### Git por SSH nos containers de aplicação

WordPress, Mautic, n8n e Evolution API encaminham o socket do `ssh-agent` do
host para `/run/host-ssh-agent`. A chave privada permanece no host; a chave
pública `.pub` não autentica operações Git por si só. Adicione a identidade ao
agente no mesmo terminal em que iniciará os containers:

```bash
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-$HOME/.ssh/docker-lab-agent.sock}"
if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
  ssh-agent -a "$SSH_AUTH_SOCK" >/dev/null
fi
ssh-add ~/.ssh/id_ed25519
ssh-add -l
```

Recrie os containers existentes para habilitar o encaminhamento:

```bash
for service in wordpress mautic n8n evolution-api; do
  (cd "$HOME/docker-shared/$service" && docker compose up -d --build --force-recreate)
done
```

O script `start-all.sh` também usa `--build` e avisa quando não encontra um
agente SSH. Sem agente ativo, os containers continuam iniciando, mas Git via
SSH não funciona. O socket concede aos processos que podem acessá-lo o uso das
identidades carregadas enquanto o container estiver em execução; encaminhe-o
somente para containers de aplicação confiáveis.

Os arquivos persistentes também estão disponíveis no host:

```bash
cd ~/lab-data/wordpress/files
```

Site: <http://wordpress.lab.local>

No momento da verificação, o WordPress consegue abrir uma conexão MySQL, mas
`wordpress` ainda não tem tabelas e a página mostra erro de banco. Não há
usuário/senha de administrador do site para informar. Depois de restaurar o
banco ou concluir uma instalação nova, use `dev@lab.local` como email de
administrador.

O serviço registra `wordpress.lab.local` como alias na rede Docker
`infra-network`. Portanto, essa mesma URL pode ser usada nas credenciais do
n8n e em integrações executadas por outros containers do laboratório.

O laboratório define `WP_ENVIRONMENT_TYPE` como `local`. Isso permite criar
Application Passwords para integrações REST em HTTP. Em produção, utilize HTTPS
e altere o tipo de ambiente para `production`.

### Banco do WordPress — MySQL

O WordPress e o MySQL leem a senha compartilhada do arquivo:

```text
~/lab-data/wordpress/secrets/db_password
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

O Mautic está na tela de instalação e o banco ainda não contém tabelas. Crie o
primeiro usuário pelo assistente usando `dev@lab.local` como email; não existe
uma senha padrão de aplicação nesta instalação.

```bash
docker exec -it mautic sh
docker exec mautic php /var/www/html/bin/console about
docker exec mautic php /var/www/html/bin/console cache:clear
docker exec mautic php /var/www/html/bin/console mautic:segments:update
docker exec mautic php /var/www/html/bin/console mautic:campaigns:update
docker exec mautic php /var/www/html/bin/console mautic:campaigns:trigger
docker exec mautic git --version
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
docker exec n8n git --version
docker logs -f --tail=200 n8n
```

O diretório do host `~/lab-data/n8n/arquivos` fica disponível dentro
do container como `/data/arquivos`. Nos nós **Read/Write Files from Disk**,
**Local File Trigger** e similares, sempre utilize o caminho interno:

```text
/data/arquivos/nome-do-arquivo.ext
```

O Compose define `N8N_RESTRICT_FILE_ACCESS_TO=/data/arquivos`, restringindo os
nós de arquivo a esse diretório.

Aplicação: <http://n8n.lab.local>

O n8n está usando SQLite, restaurado da instalação anterior. A conta existente
é `admin@lab.local`; a senha não vem do Compose e deve ser a senha já usada na
instalação antiga. Há 11 workflows e 4 credenciais restaurados. Todos os
workflows estavam inativos na origem; confira-os antes de ativar.

#### Backup do banco SQLite ativo

Use a API de backup do SQLite, que inclui os dados ainda registrados no WAL,
e guarde também o arquivo de configuração com a chave necessária para
descriptografar as credenciais:

```bash
mkdir -p ~/backups/databases
backup="$HOME/backups/databases/n8n-$(date +%F-%H%M%S).sqlite"
python3 - "$HOME/lab-data/n8n/data/.n8n/database.sqlite" "$backup" <<'PY'
import sqlite3
import sys

source = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
destination = sqlite3.connect(sys.argv[2])
source.backup(destination)
print(destination.execute("PRAGMA integrity_check").fetchone()[0])
destination.close()
source.close()
PY
install -m 600 ~/lab-data/n8n/data/.n8n/config "${backup%.sqlite}-config.json"
```

O serviço `n8n-db` (PostgreSQL) continua incluído e ativo, mas não é o banco
usado pelo n8n atual. Ele está vazio. Um dump desse PostgreSQL não contém os
workflows nem as credenciais da aplicação.

### PostgreSQL `n8n-db` (não usado pelo n8n atual)

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

O Compose ainda referencia `minio/minio`, cuja imagem não está disponível no
Docker Hub. O projeto original foi descontinuado; a opção oficial atual é
MinIO AIStor, que requer licença. Por enquanto, `start-all.sh` ignora esse
serviço para não interromper o laboratório. O Compose e os dados em
`~/lab-data/minio` foram preservados; não execute `docker compose up` nesse
diretório até escolher uma imagem compatível e confirmar seus requisitos.

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

Na validação, o Portainer informou `Administrator initialization timeout`.
Para reabrir o cadastro, reinicie o serviço e crie o administrador pela
interface em até 5 minutos:

```bash
docker compose -f ~/docker-shared/portainer/docker-compose.yml restart
```

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
No host, as portas são `1026` (SMTP) e `8026` (interface web), para evitar
conflito com outros serviços que já usem `1025` e `8025`.

Configuração SMTP para clientes dentro do Docker:

- Host: `mailhog`
- Porta: `1025`
- Segurança/TLS: desativada
- Autenticação: desativada
- Remetente e endereço de teste: `dev@lab.local`

Em 30/10/2026, foi feito um teste SMTP real a partir do namespace de rede de
cada um dos 14 containers ativos. O MailHog aceitou as 14 mensagens, que podem
ser conferidas na interface acima procurando o assunto
`DOCKER-LAB-NETWORK-TEST`. O teste usou um cliente auxiliar temporário na rede
de cada container: comprova DNS, conexão TCP e aceitação SMTP pelo MailHog,
mas **não configura o envio de email dentro de cada aplicação**. O MailHog
somente captura as mensagens e não as entrega a destinatários externos.

Para envio feito pelas próprias aplicações, configure o cliente correspondente:

- **WordPress:** configure um plugin SMTP (por exemplo, WP Mail SMTP) com os
  valores acima. O site precisa ter banco/tabelas e estar inicializado antes
  disso; atualmente ele apresenta erro de banco.
- **Mautic:** após concluir a instalação, configure o transporte de email como
  SMTP, host `mailhog`, porta `1025`, sem TLS nem autenticação, e remetente
  `dev@lab.local`.
- **n8n:** crie uma credencial SMTP para o nó **Send Email** com host `mailhog`,
  porta `1025`, sem SSL/TLS nem autenticação; use `dev@lab.local` como remetente.
- **Demais containers:** o teste confirma que alcançam o servidor SMTP, mas
  serviços como bancos, Redis, Traefik e Evolution API não têm configuração de
  envio de email declarada no Compose.

### Evolution API

```bash
docker exec -it evolution-api sh
docker exec evolution-api git --version
docker exec evolution-api node --version
docker exec evolution-api npm --version
docker logs -f --tail=200 evolution-api
docker inspect evolution-api
```

O laboratório utiliza `evoapicloud/evolution-api:v2.3.7` e força a resolução
DNS IPv4 com `NODE_OPTIONS=--dns-result-order=ipv4first`, evitando loops de
conexão do Baileys observados em versões antigas no Docker/WSL.

Aplicação: <http://evolution-api.lab.local>

Depois de qualquer alteração no Compose:

```bash
cd ~/docker-shared/evolution-api
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
docker compose -f ~/docker-shared/<servico>/docker-compose.yml config
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
