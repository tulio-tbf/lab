#!/usr/bin/env bash
# Manutenção do lab: atualizar imagens, adicionar e remover serviços e limpar
# espaço. Bancos de dados e dados removidos ganham backup automático antes de
# qualquer mudança, e o local do backup é exibido ao final.
#
# Uso: update-lab.sh [atualizar|adicionar|remover|limpar] [--base DIRETÓRIO]

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Gerado em BASE/scripts, as bibliotecas ficam ao lado; no repositório, em lib/.
if [[ -f "$SCRIPT_DIR/services.sh" ]]; then
  LIB_DIR="$SCRIPT_DIR"
  DEFAULT_BASE="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
else
  LIB_DIR="$SCRIPT_DIR/../lib"
  DEFAULT_BASE="$HOME/docker-shared"
fi
BASE="${LAB_BASE:-$DEFAULT_BASE}"
ACTION=""

usage() {
  cat <<'EOF'
Uso: update-lab.sh [AÇÃO] [--base DIRETÓRIO]

Ações:
  atualizar   Baixa ou reconstrói as imagens e recria os containers em execução
              (faz backup dos bancos envolvidos antes)
  adicionar   Cria serviços que ainda não existem, sem mexer nos demais
  remover     Remove serviços: só o container, também imagem e configuração,
              ou tudo, inclusive os dados (com backup antes)
  limpar      Apaga imagens sem uso e cache de build; opcionalmente, modelos do
              Ollama

Sem ação, um menu pergunta o que fazer.
EOF
}

while (($#)); do
  case "$1" in
    -b|--base)
      [[ $# -ge 2 ]] || { echo "Erro: $1 requer um diretório." >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    atualizar|update|adicionar|add|remover|remove|limpar|clean)
      ACTION="$1"
      shift
      ;;
    *)
      echo "Erro: argumento desconhecido: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$BASE" ]]; then
  echo "Erro: diretório base não encontrado: $BASE" >&2
  exit 1
fi
BASE="$(cd -- "$BASE" && pwd -P)"

# shellcheck source=../lib/platform.sh
source "$LIB_DIR/platform.sh"
source "$LIB_DIR/engine.sh"
# shellcheck source=../lib/services.sh
source "$LIB_DIR/services.sh"
lab_load_env "$BASE"
engine_load "$BASE" || exit 1
engine_require || exit 1

# No Git Bash, impede que caminhos passados ao docker sejam convertidos.
export MSYS_NO_PATHCONV=1

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIRS=()
BACKUP_FILES=()

confirm() {
  local reply
  read -r -p "$1 [s/N] " reply || reply=""
  case "$reply" in
    s|S|sim|SIM|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Escolhidos + bancos deles (dependências fortes), existentes, na ordem da
# lista informada.
expand_targets() {
  local service selected
  for service in "$@"; do
    lab_service_exists "$BASE" "$service" || continue
    for selected in "${LAB_SELECTED[@]}"; do
      if [[ "$service" == "$selected" ]] || in_list "$service" $(lab_strong_dependencies "$selected"); then
        echo "$service"
        break
      fi
    done
  done
  return 0
}

compose_images() {
  (cd -- "$BASE/$1" && engine_compose_images 2>/dev/null) || true
}

image_ids() {
  local image
  for image in $(compose_images "$1"); do
    engine image inspect -f '{{.Id}}' "$image" 2>/dev/null || echo "ausente:$image"
  done
  return 0
}

print_hosts_reminder() {
  printf '\nLista de hosts atualizada em %s/hosts-lab.txt. Aplique com:\n' "$BASE"
  printf '%s/scripts/update-hosts.sh\n' "$BASE"
}

#############################################
# BACKUP
#############################################

# Define BACKUP_DIR (sem subshell, para BACKUP_DIRS acumular as pastas).
backup_dir() {
  BACKUP_DIR="$LAB_BACKUPS/$1/$STAMP"
  mkdir -p "$BACKUP_DIR"
  in_list "$BACKUP_DIR" "${BACKUP_DIRS[@]+"${BACKUP_DIRS[@]}"}" || BACKUP_DIRS+=("$BACKUP_DIR")
  if [[ ! -f "$BACKUP_DIR/RESTAURAR.txt" ]]; then
    {
      printf '# No Bash, carregue a configuração da instalação de destino. Origem: %s\n' "$LAB_ENGINE"
      printf 'LAB_RESTORE_BASE=%q\n' "$BASE"
      printf '%s\n' 'source "$LAB_RESTORE_BASE/scripts/engine.sh"' \
        'engine_load "$LAB_RESTORE_BASE" || exit 1' ''
    } > "$BACKUP_DIR/RESTAURAR.txt"
  fi
}

wait_db_ready() {
  local service="$1"
  local engine attempt
  engine="$(lab_db_engine "$service")"

  for ((attempt = 0; attempt < 30; attempt++)); do
    case "$engine" in
      postgres)
        engine_exec "$service" sh -c 'pg_isready -q -U "$POSTGRES_USER"' >/dev/null 2>&1 && return 0
        ;;
      mysql)
        engine_exec "$service" sh -c 'c=$(command -v mariadb-admin || command -v mysqladmin); MYSQL_PWD="$MYSQL_ROOT_PASSWORD" "$c" -uroot ping' >/dev/null 2>&1 && return 0
        ;;
    esac
    sleep 2
  done
  return 1
}

# Dump completo do banco em BACKUPS/databases/<data>/<serviço>.sql.gz. Se o
# container estiver parado, sobe só durante o dump.
backup_database() {
  local service="$1"
  local engine dir file started=0 status=0
  engine="$(lab_db_engine "$service")"
  [[ -n "$engine" && -f "$BASE/$service/docker-compose.yml" ]] || return 0

  if ! lab_container_running "$service"; then
    echo "Iniciando $service temporariamente para o backup"
    (cd -- "$BASE/$service" && engine_compose up -d) || return 1
    started=1
  fi

  if ! wait_db_ready "$service"; then
    echo "Erro: $service não ficou pronto para o backup." >&2
    status=1
  else
    backup_dir databases
    dir="$BACKUP_DIR"
    file="$dir/$service.sql.gz"
    echo "Backup do banco $service"
    case "$engine" in
      postgres)
        engine_exec "$service" sh -c 'exec pg_dumpall -U "$POSTGRES_USER"' | gzip > "$file" || status=1
        ;;
      mysql)
        engine_exec "$service" sh -c 'd=$(command -v mariadb-dump || command -v mysqldump); MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$d" -uroot --all-databases --single-transaction --routines --events' | gzip > "$file" || status=1
        ;;
    esac

    if ((status)); then
      rm -f -- "$file"
      echo "Erro: falha no backup de $service." >&2
    else
      BACKUP_FILES+=("$file")
      {
        echo "# $service ($engine)"
        if [[ "$engine" == "postgres" ]]; then
          echo "gunzip -c $(printf '%q' "$file") | engine_exec -i $service sh -c 'psql -U \"\$POSTGRES_USER\" -d postgres'"
        else
          echo "gunzip -c $(printf '%q' "$file") | engine_exec -i $service sh -c 'c=\$(command -v mariadb || command -v mysql); MYSQL_PWD=\"\$MYSQL_ROOT_PASSWORD\" exec \"\$c\" -uroot'"
        fi
        echo
      } >> "$dir/RESTAURAR.txt"
    fi
  fi

  if ((started)); then
    (cd -- "$BASE/$service" && engine_compose stop) >/dev/null 2>&1 || true
  fi
  return "$status"
}

# Compacta um diretório ou arquivo do host, ou um volume Docker. Usa um
# container docker.io/library/alpine para ler arquivos de outros usuários (mysql, www-data) sem
# sudo.
backup_archive() {
  local kind="$1"   # dir | volume (dir também aceita um arquivo)
  local source="$2"
  local name="$3"
  local dir mount item="."

  case "$kind" in
    dir)
      if [[ -f "$source" ]]; then
        item="$(basename -- "$source")"
        source="$(dirname -- "$source")"
      elif [[ ! -d "$source" ]]; then
        return 0
      fi
      ;;
    volume) engine_volume_exists "$source" || return 0 ;;
  esac
  backup_dir volumes
  dir="$BACKUP_DIR"
  mount="$source:/src:ro"

  echo "Backup de $name"
  if ! engine_data_run -v "$mount" -v "$dir:/backup" docker.io/library/alpine \
    tar czf "/backup/$name.tar.gz" -C /src "$item"; then
    echo "Erro: falha no backup de $name." >&2
    return 1
  fi
  BACKUP_FILES+=("$dir/$name.tar.gz")
  {
    echo "# $name"
    if [[ "$kind" == "volume" ]]; then
      echo "engine_volume_create $source"
    else
      printf 'mkdir -p -- %q\n' "$source"
    fi
    printf 'engine_data_run -v %q -v %q docker.io/library/alpine tar xzf %q -C /dst\n' \
      "$source:/dst" "$dir:/backup:ro" "/backup/$name.tar.gz"
    echo
  } >> "$dir/RESTAURAR.txt"
}

print_backup_summary() {
  local file dir
  ((${#BACKUP_FILES[@]})) || return 0

  printf '\n=== Backup criado ===\n'
  for dir in "${BACKUP_DIRS[@]}"; do
    printf 'Pasta: %s\n' "$dir"
  done
  for file in "${BACKUP_FILES[@]}"; do
    printf '  %-8s %s\n' "$(du -h "$file" | cut -f1)" "$file"
  done
  printf 'Como restaurar: veja RESTAURAR.txt na pasta do backup.\n'
}

#############################################
# ATUALIZAR
#############################################

action_update() {
  local service rel before after targets=() updated=() unchanged=() failed=() stopped=()

  LAB_CHOICES=()
  for service in "${LAB_START_ORDER[@]}"; do
    lab_service_exists "$BASE" "$service" && LAB_CHOICES+=("$service")
  done
  if ((${#LAB_CHOICES[@]} == 0)); then
    echo "Nenhum serviço criado em $BASE." >&2
    return 1
  fi
  LAB_MENU_RUNNING="$(engine ps --format '{{.Names}}' | tr '\n' ' ')"
  lab_choose_services "atualizar" || return 1

  while IFS= read -r service; do
    targets+=("$service")
  done < <(expand_targets "${LAB_START_ORDER[@]}")
  printf '\nSerão atualizados (com os bancos): %s\n\n' "${targets[*]}"

  # Backup de todos os bancos envolvidos (e do estado em SQLite) antes de
  # baixar qualquer imagem. Se um falhar, nada é atualizado.
  for service in "${targets[@]}"; do
    if [[ -n "$(lab_db_engine "$service")" ]] && ! backup_database "$service"; then
      print_backup_summary
      echo "Atualização cancelada: o backup de $service falhou. Nenhuma imagem foi alterada." >&2
      return 1
    fi
    for rel in $(lab_service_state_paths "$service"); do
      if ! backup_archive dir "$LAB_DATA/$rel" "estado-$service"; then
        print_backup_summary
        echo "Atualização cancelada: o backup de $service falhou. Nenhuma imagem foi alterada." >&2
        return 1
      fi
    done
  done
  print_backup_summary

  for service in "${targets[@]}"; do
    printf '\n--- %s\n' "$service"
    if [[ -f "$BASE/$service/EXTERNAL.txt" ]]; then
      echo "Roda fora do engine; atualize-o no próprio sistema:"
      case "$(lab_platform)" in
        macos) echo "  brew upgrade ollama (ou pelo app do Ollama)" ;;
        *) echo "  reinstale pelo instalador oficial (https://ollama.com/download)" ;;
      esac
      continue
    fi

    before="$(image_ids "$service")"
    if grep -qE '^[[:space:]]+build:' "$BASE/$service/docker-compose.yml"; then
      echo "Reconstruindo a imagem com a base mais recente"
      (cd -- "$BASE/$service" && engine_compose build --pull) || { failed+=("$service"); continue; }
    else
      (cd -- "$BASE/$service" && engine_compose pull) || { failed+=("$service"); continue; }
    fi
    after="$(image_ids "$service")"

    if lab_container_running "$service"; then
      # Recria só se a imagem mudou.
      if [[ "$before" != "$after" ]]; then
        (cd -- "$BASE/$service" && engine_compose up -d --force-recreate) || { failed+=("$service"); continue; }
      fi
    else
      stopped+=("$service")
    fi

    if [[ "$before" == "$after" ]]; then
      unchanged+=("$service")
    else
      updated+=("$service")
    fi
  done

  printf '\nRemovendo imagens antigas que ficaram sem uso\n'
  engine image prune -f | tail -n 1

  printf '\n=== Resultado ===\n'
  ((${#updated[@]})) && printf 'Atualizados:          %s\n' "${updated[*]}"
  ((${#unchanged[@]})) && printf 'Já estavam em dia:    %s\n' "${unchanged[*]}"
  ((${#stopped[@]})) && printf 'Parados (nova imagem no próximo start): %s\n' "${stopped[*]}"
  if ((${#failed[@]})); then
    printf 'Falharam:             %s\n' "${failed[*]}" >&2
  fi
  for rel in "${BACKUP_DIRS[@]+"${BACKUP_DIRS[@]}"}"; do
    printf 'Backup:               %s\n' "$rel"
  done
  ((${#failed[@]} == 0))
}

#############################################
# ADICIONAR
#############################################

action_add() {
  local service installer start_list=()

  installer="${LAB_REPO:-}/create-lab.sh"
  if [[ ! -x "$installer" ]]; then
    installer="$SCRIPT_DIR/../create-lab.sh"
  fi
  if [[ ! -x "$installer" ]]; then
    echo "Erro: create-lab.sh não encontrado. Execute a partir do repositório do lab" >&2
    echo "ou defina LAB_REPO em $BASE/lab.env." >&2
    return 1
  fi

  LAB_CHOICES=()
  for service in "${LAB_ALL_SERVICES[@]}"; do
    [[ "$LAB_ENGINE:$service" != podman:portainer ]] || continue
    lab_service_exists "$BASE" "$service" || LAB_CHOICES+=("$service")
  done
  if ((${#LAB_CHOICES[@]} == 0)); then
    echo "Todos os serviços já existem em $BASE."
    return 0
  fi
  LAB_MENU_RUNNING=""
  lab_choose_services "adicionar" || return 1

  "$installer" --base "$BASE" --data "$LAB_DATA" --backups "$LAB_BACKUPS" \
    --domain "$LAB_DOMAIN" --services "${LAB_SELECTED[*]}"

  for service in "${LAB_START_ORDER[@]}"; do
    if lab_selection_requires "$service" && lab_service_exists "$BASE" "$service"; then
      start_list+=("$service")
    fi
  done

  if ((${#start_list[@]})) && confirm $'\n'"Iniciar agora (${start_list[*]})?"; then
    lab_check_ssh_agent
    lab_compose_up "$BASE" "${start_list[@]}"
  fi
}

#############################################
# REMOVER
#############################################

action_remove() {
  local service other level phrase reply images=() targets=() dependents=() failed=0 rel vol

  LAB_CHOICES=()
  while IFS= read -r service; do
    LAB_CHOICES+=("$service")
  done < <(lab_existing_services "$BASE")
  if ((${#LAB_CHOICES[@]} == 0)); then
    echo "Nenhum serviço criado em $BASE."
    return 0
  fi
  LAB_MENU_RUNNING="$(engine ps --format '{{.Names}}' | tr '\n' ' ')"
  lab_choose_services "remover" || return 1

  # Ordem inversa da inicialização: aplicações antes dos bancos e do
  # traefik. O minio não está na ordem de início e entra primeiro.
  local order=(minio)
  for ((other = ${#LAB_START_ORDER[@]} - 1; other >= 0; other--)); do
    order+=("${LAB_START_ORDER[other]}")
  done
  while IFS= read -r service; do
    targets+=("$service")
  done < <(expand_targets "${order[@]}")
  printf '\nSerão removidos (com os bancos): %s\n' "${targets[*]}"

  # Serviços que ficam e dependem de algum que sai.
  for other in "${LAB_CHOICES[@]}"; do
    in_list "$other" "${targets[@]}" && continue
    for service in "${targets[@]}"; do
      if lab_service_requires "$other" "$service"; then
        dependents+=("$other precisa de $service")
      fi
    done
  done
  if ((${#dependents[@]})); then
    printf '\nAtenção, serviços que continuam no lab dependem dos removidos:\n'
    printf '  %s\n' "${dependents[@]}"
    confirm "Remover mesmo assim?" || { echo "Cancelado."; return 1; }
  fi

  cat <<'EOF'

O que remover?
  1) Só o container: configuração e dados ficam; volta com start-all/start-custom
  2) Container, imagem e configuração: os dados ficam; adicionar de novo os recupera
  3) Tudo, inclusive dados e volumes (backup automático antes)
EOF
  read -r -p "Nível [1-3]: " level || level=""

  case "$level" in
    1)
      for service in "${targets[@]}"; do
        [[ -f "$BASE/$service/docker-compose.yml" ]] || continue
        echo "Parando e removendo o container $service"
        (cd -- "$BASE/$service" && engine_compose down) || failed=1
      done
      return "$failed"
      ;;
    2)
      confirm "Remover container, imagem e configuração de: ${targets[*]}?" || { echo "Cancelado."; return 1; }
      ;;
    3)
      if ((${#targets[@]} == 1)); then
        phrase="${targets[0]}"
      else
        phrase="apagar ${#targets[@]} serviços"
      fi
      printf '\nIsso apaga os dados de: %s\n' "${targets[*]}"
      read -r -p "Para confirmar, digite \"$phrase\": " reply || reply=""
      [[ "$reply" == "$phrase" ]] || { echo "Confirmação diferente; cancelado."; return 1; }

      # Dump dos bancos enquanto ainda rodam; depois para tudo e arquiva
      # volumes, dados e configuração. Qualquer falha cancela antes de apagar.
      for service in "${targets[@]}"; do
        if [[ -n "$(lab_db_engine "$service")" ]] && ! backup_database "$service"; then
          print_backup_summary
          echo "Remoção cancelada: o backup de $service falhou. Nada foi apagado." >&2
          return 1
        fi
      done
      ;;
    *)
      echo "Nível inválido; cancelado."
      return 1
      ;;
  esac

  for service in "${targets[@]}"; do
    [[ -f "$BASE/$service/docker-compose.yml" ]] || continue
    while IFS= read -r other; do
      [[ -n "$other" ]] && images+=("$other")
    done < <(compose_images "$service")
    echo "Parando e removendo o container $service"
    (cd -- "$BASE/$service" && engine_compose down) || failed=1
  done

  ((failed == 0)) || return 1

  if [[ "$level" == "3" ]]; then
    for service in "${targets[@]}"; do
      for vol in $(lab_service_volumes "$service"); do
        backup_archive volume "$vol" "volume-$vol" || failed=1
      done
      for rel in $(lab_service_data_dirs "$service"); do
        backup_archive dir "$LAB_DATA/$rel" "dados-${rel//\//_}" || failed=1
      done
      backup_archive dir "$BASE/$service" "config-$service" || failed=1
    done
    if ((failed)); then
      print_backup_summary
      echo "Remoção interrompida: algum backup falhou. Os containers foram parados, mas nada foi apagado." >&2
      return 1
    fi

    for service in "${targets[@]}"; do
      for vol in $(lab_service_volumes "$service"); do
        engine_volume_exists "$vol" || continue
        echo "Apagando o volume $vol"
        engine_volume_remove "$vol" >/dev/null || failed=1
      done
      for rel in $(lab_service_data_dirs "$service"); do
        [[ -d "$LAB_DATA/$rel" ]] || continue
        echo "Apagando $LAB_DATA/$rel"
        engine_data_run -v "$LAB_DATA:/data" docker.io/library/alpine rm -rf "/data/$rel" || failed=1
      done
    done
  fi

  for service in "${targets[@]}"; do
    echo "Apagando a configuração $BASE/$service"
    # Arquivos criados por containers podem pertencer a outro usuário.
    rm -rf -- "${BASE:?}/$service" 2>/dev/null \
      || engine_data_run -v "$BASE:/base" docker.io/library/alpine rm -rf "/base/$service" \
      || failed=1
  done

  for other in "${images[@]+"${images[@]}"}"; do
    if engine_image_remove "$other" >/dev/null 2>&1; then
      echo "Imagem removida: $other"
    else
      echo "Imagem mantida (em uso por outro container ou já ausente): $other"
    fi
  done

  if in_list ollama "${targets[@]}"; then
    echo "Ollama nativo, se houver, continua instalado no sistema com seus modelos."
  fi

  lab_write_hosts "$BASE" "$LAB_DOMAIN"
  print_backup_summary
  print_hosts_reminder
  return "$failed"
}

#############################################
# LIMPAR
#############################################

ollama_command() {
  local mode
  mode="$(sed -n 's/^OLLAMA_MODE=//p' "$BASE/ollama/ollama.env" 2>/dev/null || true)"
  case "$mode" in
    docker|docker-gpu) lab_container_running ollama && echo "engine_exec ollama ollama" ;;
    native)
      if command -v ollama >/dev/null 2>&1; then
        echo "ollama"
      elif command -v ollama.exe >/dev/null 2>&1; then
        echo "ollama.exe"
      fi
      ;;
  esac
  return 0
}

action_clean() {
  local ollama models model

  printf '\nUso de disco antes:\n'
  engine system df

  printf '\nRemovendo imagens sem tag (versões antigas substituídas)\n'
  engine image prune -f | tail -n 1
  if [[ "$LAB_ENGINE" == docker ]]; then
    printf '\nRemovendo o cache de build\n'
    engine_build_cache_prune | tail -n 1
  fi

  printf '\nUso de disco depois:\n'
  engine system df
  echo "Volumes e imagens de serviços parados não são tocados."

  ollama="$(ollama_command)"
  if [[ -n "$ollama" ]]; then
    printf '\nModelos do Ollama:\n'
    $ollama list
    read -r -p "Modelos para apagar (nomes separados por espaço, Enter para nenhum): " models || models=""
    for model in $models; do
      $ollama rm "$model" || true
    done
  elif [[ -d "$BASE/ollama" ]]; then
    echo "Ollama não está acessível agora; inicie-o para gerenciar os modelos."
  fi
}

#############################################
# MENU
#############################################

if [[ -z "$ACTION" ]]; then
  cat <<'EOF'

O que deseja fazer?
  1) Atualizar  imagens dos serviços (backup automático dos bancos)
  2) Adicionar  serviços que ainda não existem
  3) Remover    serviços
  4) Limpar     imagens antigas, cache de build e modelos do Ollama
EOF
  read -r -p "Opção [1-4]: " ACTION || exit 1
fi

case "$ACTION" in
  1|atualizar|update) action_update ;;
  2|adicionar|add) action_add ;;
  3|remover|remove) action_remove ;;
  4|limpar|clean) action_clean ;;
  *) echo "Opção inválida: $ACTION" >&2; exit 2 ;;
esac
