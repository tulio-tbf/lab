# Guia de administração do Lab com Podman

O MVP do Lab tem como alvo Linux nativo com Podman rootless. A configuração
gerada passou por validação estática. A execução integrada em Linux nativo
ainda está pendente. O fluxo do Lab para Podman em WSL, macOS e Windows está
fora do escopo deste MVP.

## Preparar o host e instalar

Instale Podman, o provider `podman-compose` 1.5 ou superior, Netavark com
Aardvark DNS e `curl`. O caminho inicial do Lab foi documentado para Podman 5.x.
Use um usuário comum com mapeamentos em `/etc/subuid` e `/etc/subgid`.

```bash
podman info --format '{{.Host.Security.Rootless}}'
PODMAN_COMPOSE_PROVIDER=podman-compose podman compose version
systemctl --user enable --now podman.socket
curl -fsS --unix-socket "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock" \
  http://localhost/_ping
```

Na raiz do repositório, instale em uma base própria e use um diretório de dados
vazio. O instalador grava `LAB_ENGINE=podman` em `lab.env`.

```bash
./install.sh --engine podman --base "$HOME/podman-lab" \
  --data "$HOME/podman-lab-data" --backups "$HOME/podman-lab-backups" \
  --services "wordpress n8n"
cd "$HOME/podman-lab"
./scripts/update-hosts.sh
./scripts/start-all.sh
```

## Iniciar, parar e manter

Execute os scripts a partir da base da instalação. Eles selecionam a engine
registrada em `lab.env`.

```bash
./scripts/start-custom.sh
./scripts/stop-all.sh
./scripts/update-lab.sh
```

O menu de manutenção permite atualizar imagens, adicionar ou remover serviços
e limpar imagens pendentes. O Portainer fica desabilitado no modo Podman.
Use os scripts do Lab e a CLI do Podman para administrar os containers.

## Diagnosticar serviços

Para inspecionar um serviço com o mesmo provider usado pelos scripts,
abra o diretório do projeto Compose correspondente.

```bash
cd ~/podman-lab/n8n
PODMAN_COMPOSE_PROVIDER=podman-compose podman compose config
PODMAN_COMPOSE_PROVIDER=podman-compose podman compose ps
podman logs --tail 200 n8n
podman logs --tail 200 traefik
podman network inspect infra-network
```

- **Traefik.** O provider Docker usa a API de compatibilidade do Podman.
  O socket rootless fica em `${XDG_RUNTIME_DIR}/podman/podman.sock`, normalmente
  `/run/user/<uid>/podman/podman.sock`. A rede externa `infra-network`
  serve ao proxy e à resolução de nomes entre projetos. O socket permite
  controlar containers do usuário, mesmo quando montado como somente leitura.
  [API do Podman](https://docs.podman.io/en/stable/markdown/podman-system-service.1.html)
- **Portas.** Use `http://traefik.lab.test:8000/dashboard/` e
  `http://n8n.lab.test:8000/` com os padrões do Podman. Se precisar da porta 80,
  use `--http-port 80` quando a política de `net.ipv4.ip_unprivileged_port_start`
  do host permitir. Reduzir esse limite permite que outros usuários do host
  também ocupem as portas liberadas. O Lab atual publica HTTP. Se você configurar HTTPS na porta 443, vale a mesma restrição. Docker continua com HTTP
  na porta 80 por padrão. Se os dois engines rodarem simultaneamente, evite
  colisões nas demais portas publicadas, como a 8088 do painel.
- **Volumes e SELinux.** O Podman usa `:Z` para os bind mounts privados e `:z`
  no arquivo compartilhado entre WordPress e MySQL. O Traefik usa
  `label=disable` para acessar o socket da API sem mudar seu rótulo no host.
  O n8n mapeia o usuário da instalação para UID/GID 1000 no container.
  Outros serviços podem criar arquivos com IDs subordinados. Inspecione-os
  com `podman unshare`, mantendo o proprietário original dos arquivos.
- **SSH.** O script encaminha o socket ativo de `SSH_AUTH_SOCK`. Confirme a
  identidade dentro do serviço que usa Git, pois a permissão depende do usuário
  da imagem e da política SELinux. O socket do agente mantém o rótulo do host.
- **Ollama.** Use `--ollama-mode docker` para o container CPU com qualquer
  engine. Em modo nativo, Podman usa `http://host.containers.internal:11434`
  e Docker usa `http://host.docker.internal:11434`. O Ollama precisa escutar
  num endereço alcançável pelo container. O modo remoto usa a URL explícita
  de `--ollama-url`. GPU em container via `docker-gpu` continua restrita ao
  caminho Docker com NVIDIA. Em Podman, use Ollama nativo ou remoto para
  aceleração NVIDIA ou AMD de acordo com o suporte do host.
- **Compose.** O Lab seleciona explicitamente `podman-compose`.
  Os builds locais usam tags `localhost/` e as imagens públicas têm registry
  explícito. Como esse provider não oferece `config --images`, a manutenção
  lê as imagens declaradas no Compose resolvido. A limpeza em Podman remove
  imagens pendentes. A limpeza separada do cache de build usa o comando do Docker.
  [Seleção do provider](https://docs.podman.io/en/stable/markdown/podman-compose.1.html)

## Verificação em Linux nativo

Com uma base descartável, inicie WordPress, n8n e Evolution API com os scripts
do Lab. Confirme que as imagens do WordPress e da Evolution API foram construídas localmente, que
os serviços aparecem em `podman ps`, que o PostgreSQL fica saudável e que a
aplicação resolve os aliases dos serviços pela `infra-network`. Crie um dado
de teste e verifique a persistência após parar e iniciar o Lab. Confira também
as variáveis do n8n, as permissões dos arquivos no host e a política de
reinício em `podman inspect`.

```bash
curl -fsS -H 'Host: traefik.lab.test' http://127.0.0.1:8000/dashboard/
curl -fsS -H 'Host: n8n.lab.test' http://127.0.0.1:8000/healthz
podman stop n8n
# Aguarde o Traefik processar o evento e confirme a retirada da rota.
podman start n8n
# Aguarde a aplicação e confirme que a mesma URL volta a responder.
```

Teste SSH com uma operação Git no serviço que deve usar o agente, e o Ollama
nativo consultando `/api/tags` a partir de um container. Exercite backup e
restauração com dados descartáveis, incluindo um volume nomeado e um dump SQL.
A configuração gerada foi verificada estaticamente, com execução integrada,
eventos do Traefik, permissões SELinux e GPU ainda pendentes.

## Restaurar em outra instalação

1. Faça backup de bancos e dados na instalação de origem e conserve os
   arquivos `RESTAURAR.txt` de cada lote.
2. Crie uma instalação no engine de destino com outra base e outro diretório
   de dados. Os volumes com o mesmo nome pertencem ao armazenamento de cada
   engine e precisam ser restaurados no destino.
3. Em Bash, adapte `LAB_RESTORE_BASE` nas instruções geradas para apontar
   para a base de destino. Adapte também os caminhos de destino dos bind
   mounts. Execute os comandos de restauração dos dados com os aplicativos
   parados. Para importar os dumps SQL, inicie os respectivos bancos.
   Preserve os arquivos Compose recém-gerados para o destino e reaplique
   personalizações de configuração manualmente.
