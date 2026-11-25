# Catálogo de serviços do lab, dependências e menu de seleção, compartilhados
# por create-lab.sh e start-custom.sh. Carregado com `source`; não execute
# diretamente. Compatível com o Bash 3.2 do macOS (sem arrays associativos,
# mapfile ou namerefs).

# Ordem de criação.
LAB_ALL_SERVICES=(traefik wordpress wordpress-db mautic mautic-db n8n redis minio portainer adminer pgadmin mailhog evolution-db evolution-api ollama qdrant open-webui searxng)
LAB_AI_SERVICES=(ollama qdrant open-webui searxng)

# Ordem de inicialização: bancos e infraestrutura antes das aplicações. O
# minio fica de fora (imagem configurada indisponível; veja start-all.sh).
LAB_START_ORDER=(traefik wordpress-db mautic-db redis wordpress mautic n8n portainer adminer pgadmin mailhog evolution-db evolution-api ollama qdrant searxng open-webui)

lab_service_dependencies() {
  case "$1" in
    wordpress) echo "wordpress-db traefik" ;;
    mautic) echo "mautic-db traefik" ;;
    n8n|minio|portainer|adminer|pgadmin|mailhog|qdrant|searxng) echo "traefik" ;;
    evolution-api) echo "evolution-db redis traefik" ;;
    open-webui) echo "ollama traefik" ;;
  esac
}

# Verdadeiro se $1 é $2 ou depende de $2, direta ou indiretamente.
lab_service_requires() {
  local service="$1"
  local target="$2"
  local dep

  if [[ "$service" == "$target" ]]; then
    return 0
  fi

  for dep in $(lab_service_dependencies "$service"); do
    if [[ "$dep" == "$target" ]] || lab_service_requires "$dep" "$target"; then
      return 0
    fi
  done

  return 1
}

# Verdadeiro se algum serviço de LAB_SELECTED precisa de $1.
lab_selection_requires() {
  local service="$1"
  local selected

  for selected in "${LAB_SELECTED[@]}"; do
    if lab_service_requires "$selected" "$service"; then
      return 0
    fi
  done

  return 1
}

_lab_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

_lab_print_menu() {
  local columns=3
  local count=${#LAB_MENU[@]}
  local rows=$(((count + columns - 1) / columns))
  local row column index label

  for ((row = 0; row < rows; row++)); do
    for ((column = 0; column < columns; column++)); do
      index=$((column * rows + row))
      if ((index < count)); then
        label="${LAB_MENU[index]}"
        if [[ " ${LAB_MENU_RUNNING:-} " == *" $label "* ]]; then
          label="$label *"
        fi
        printf '  %2d) %-18s' "$((index + 1))" "$label"
      fi
    done
    printf '\n'
  done
}

# Converte a resposta em LAB_SELECTED. Aceita nomes, números, intervalos (3-5)
# e os atalhos A e IA, separados por espaço ou vírgula.
_lab_parse_answer() {
  local answer="$1"
  local token first last number service found count=${#LAB_MENU[@]}

  LAB_SELECTED=()
  answer="$(printf '%s' "$answer" | tr '[:upper:],' '[:lower:] ')"

  for token in $answer; do
    case "$token" in
      a|all|todos)
        LAB_SELECTED+=("${LAB_CHOICES[@]}")
        ;;
      ia|ai)
        found=0
        for service in "${LAB_AI_SERVICES[@]}"; do
          if _lab_in_list "$service" "${LAB_CHOICES[@]}"; then
            LAB_SELECTED+=("$service")
            found=1
          fi
        done
        if ((!found)); then
          echo "Nenhum serviço de IA disponível." >&2
          return 1
        fi
        ;;
      *)
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          first=$((10#${BASH_REMATCH[1]}))
          last=$((10#${BASH_REMATCH[2]}))
          if ((first < 1 || last > count || first > last)); then
            echo "Intervalo inválido: $token (use números de 1 a $count)" >&2
            return 1
          fi
          for ((number = first; number <= last; number++)); do
            LAB_SELECTED+=("${LAB_MENU[number - 1]}")
          done
        elif [[ "$token" =~ ^[0-9]+$ ]]; then
          number=$((10#$token))
          if ((number < 1 || number > count)); then
            echo "Número inválido: $token (use números de 1 a $count)" >&2
            return 1
          fi
          LAB_SELECTED+=("${LAB_MENU[number - 1]}")
        elif _lab_in_list "$token" "${LAB_CHOICES[@]}"; then
          # Bancos não aparecem no menu, mas podem ser digitados pelo nome.
          LAB_SELECTED+=("$token")
        else
          echo "Serviço inválido ou indisponível: $token" >&2
          return 1
        fi
        ;;
    esac
  done

  if ((${#LAB_SELECTED[@]} == 0)); then
    echo "Nenhum serviço informado." >&2
    return 1
  fi
}

# Mostra o menu e lê a escolha até ela ser válida.
#   $1          verbo da pergunta (criar, iniciar)
#   LAB_CHOICES serviços que podem ser escolhidos (A seleciona todos)
#   LAB_MENU_RUNNING (opcional) nomes marcados com * no menu
# Resultado em LAB_SELECTED. Os bancos (*-db) ficam fora do menu, porque
# entram sempre junto com a aplicação dona deles.
lab_choose_services() {
  local verb="$1"
  local service answer ai_list=""

  LAB_MENU=()
  while IFS= read -r service; do
    [[ -n "$service" ]] && LAB_MENU+=("$service")
  done < <(printf '%s\n' "${LAB_CHOICES[@]}" | grep -v -- '-db$' | LC_ALL=C sort)

  if ((${#LAB_MENU[@]} == 0)); then
    echo "Nenhum serviço disponível." >&2
    return 1
  fi

  for service in "${LAB_AI_SERVICES[@]}"; do
    if _lab_in_list "$service" "${LAB_CHOICES[@]}"; then
      ai_list="${ai_list:+$ai_list }$service"
    fi
  done

  printf "\nEscolha o que deseja %s:\n" "$verb"
  printf "   A = todos os serviços (padrão)\n"
  if [[ -n "$ai_list" ]]; then
    printf "  IA = somente os serviços de IA (%s)\n" "$ai_list"
  fi
  if ((${#LAB_MENU[@]} >= 2)); then
    printf "  ou informe nomes ou números separados por espaço, por exemplo: 1 2 ou %s %s\n" \
      "${LAB_MENU[0]}" "${LAB_MENU[1]}"
  else
    printf "  ou informe o nome ou o número do serviço\n"
  fi
  printf "  Intervalos também valem: 1-%s\n" "$(( ${#LAB_MENU[@]} < 4 ? ${#LAB_MENU[@]} : 4 ))"
  printf "  Bancos de dados e demais dependências entram automaticamente.\n\n"
  _lab_print_menu
  if [[ -n "${LAB_MENU_RUNNING:-}" ]]; then
    printf "\n  * já está rodando\n"
  fi
  printf "\n"

  while true; do
    if ! read -r -p "Opção: " answer; then
      echo
      echo "Entrada encerrada; nenhum serviço selecionado." >&2
      return 1
    fi
    [[ -n "${answer//[[:space:]]/}" ]] || answer="A"
    if _lab_parse_answer "$answer"; then
      return 0
    fi
    echo "Tente novamente." >&2
  done
}

#############################################
# Estado do lab em disco
#############################################

# Serviços publicados pelo Traefik em <serviço>.<domínio>.
LAB_WEB_SERVICES=(traefik wordpress mautic n8n minio portainer adminer pgadmin mailhog evolution-api qdrant open-webui searxng)

# Um serviço existe quando tem docker-compose.yml ou roda fora do engine
# (EXTERNAL.txt, como o Ollama nativo ou remoto).
lab_service_exists() {
  local base="$1"
  local service="$2"
  [[ -f "$base/$service/docker-compose.yml" || -f "$base/$service/EXTERNAL.txt" ]]
}

# Serviços existentes em BASE, na ordem de criação.
lab_existing_services() {
  local base="$1"
  local service
  for service in "${LAB_ALL_SERVICES[@]}"; do
    lab_service_exists "$base" "$service" && echo "$service"
  done
  return 0
}

# Regrava hosts-lab.txt com todos os serviços web existentes, não só os da
# última execução, para que adicionar um serviço não apague os demais.
lab_write_hosts() {
  local base="$1"
  local domain="$2"
  local service

  : > "$base/hosts-lab.txt"
  for service in "${LAB_WEB_SERVICES[@]}"; do
    if lab_service_exists "$base" "$service"; then
      printf '127.0.0.1 %s.%s\n' "$service" "$domain" >> "$base/hosts-lab.txt"
    fi
  done
}

# Dependências fortes: os bancos (*-db) pertencem à aplicação e saem junto
# com ela. As demais (traefik, redis, ollama) são compartilhadas.
lab_strong_dependencies() {
  local dep
  for dep in $(lab_service_dependencies "$1"); do
    [[ "$dep" == *-db ]] && echo "$dep"
  done
  return 0
}

# Diretórios em DATA e volumes nomeados de cada serviço.
lab_service_data_dirs() {
  case "$1" in
    wordpress|n8n|redis|minio|portainer|pgadmin|evolution-api|ollama|open-webui|qdrant) echo "$1" ;;
  esac
}

lab_service_volumes() {
  case "$1" in
    wordpress-db) echo "wordpress-db-data" ;;
    mautic-db) echo "mautic-db-data" ;;
    mautic) echo "mautic-config-data mautic-media-files-data mautic-media-images-data mautic-logs-data" ;;
    evolution-db) echo "evolution-db-data" ;;
    pgadmin) echo "pgadmin-data" ;;
  esac
}

# Estado em arquivo (SQLite) dentro de DATA, salvo antes de atualizar. O n8n
# usa o SQLite padrão dele, sem banco separado.
lab_service_state_paths() {
  case "$1" in
    n8n) echo "n8n/data/.n8n" ;;
    open-webui) echo "open-webui/webui.db" ;;
  esac
}

# Motor do banco, para backup e restauração.
lab_db_engine() {
  case "$1" in
    wordpress-db|mautic-db) echo "mysql" ;;
    evolution-db) echo "postgres" ;;
  esac
}

lab_container_running() {
  [[ "$(engine container inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == "true" ]]
}

# Sobe os serviços informados (já na ordem certa). Retorna erro se algum
# falhar; os demais continuam.
lab_compose_up() {
  local base="$1"
  shift
  local service failed=()

  for service in "$@"; do
    if [[ -f "$base/$service/EXTERNAL.txt" ]]; then
      echo "$service roda fora do engine:"
      sed 's/^/  /' "$base/$service/EXTERNAL.txt"
      continue
    fi
    [[ -f "$base/$service/docker-compose.yml" ]] || continue

    echo "Subindo $service"
    if ! (cd -- "$base/$service" && engine_compose up -d --build); then
      failed+=("$service")
    fi
  done

  if ((${#failed[@]})); then
    printf 'Erro: falha ao subir os seguintes serviços: %s\n' "${failed[*]}" >&2
    return 1
  fi
}

# Carrega BASE/lab.env (gravado pelo create-lab.sh). Para instalações antigas,
# sem o arquivo, usa os padrões e deduz o domínio pelo hosts-lab.txt.
lab_load_env() {
  local base="$1"
  local domain_line

  LAB_DATA="${LAB_DATA:-}"
  LAB_BACKUPS="${LAB_BACKUPS:-}"
  LAB_DOMAIN="${LAB_DOMAIN:-}"
  LAB_REPO="${LAB_REPO:-}"
  if [[ -f "$base/lab.env" ]]; then
    # shellcheck source=/dev/null
    source "$base/lab.env"
  fi
  if [[ -z "$LAB_DOMAIN" && -f "$base/hosts-lab.txt" ]]; then
    domain_line="$(awk '{ print $2; exit }' "$base/hosts-lab.txt")"
    LAB_DOMAIN="${domain_line#*.}"
  fi
  LAB_DATA="${LAB_DATA:-$HOME/lab-data}"
  LAB_BACKUPS="${LAB_BACKUPS:-$HOME/backups}"
  LAB_DOMAIN="${LAB_DOMAIN:-lab.test}"
}
