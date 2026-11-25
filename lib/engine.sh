# Operações de container compartilhadas pelos scripts do Lab.

engine_validate() {
  case "$1" in
    docker|podman) return 0 ;;
    *) printf 'Erro: engine inválido (%s). Use docker ou podman.\n' "$1" >&2; return 2 ;;
  esac
}

engine_configured() (
  # O ambiente do shell não substitui a escolha de uma instalação.
  local data_engine
  unset LAB_ENGINE LAB_DATA
  if [[ -f "$1/lab.env" ]]; then
    source "$1/lab.env" || return
  fi
  engine_validate "${LAB_ENGINE-docker}" || return
  if [[ -n "${LAB_DATA:-}" && -f "$LAB_DATA/.lab-engine" ]]; then
    if ! read -r data_engine < "$LAB_DATA/.lab-engine" || [[ "$data_engine" != "${LAB_ENGINE-docker}" ]]; then
      printf 'Erro: o engine de %s não corresponde ao diretório de dados %s.\n' "$1" "$LAB_DATA" >&2
      return 2
    fi
  fi
  printf '%s\n' "${LAB_ENGINE-docker}"
)

engine_load() {
  LAB_ENGINE="$(engine_configured "$1")"
}

engine() {
  case "${LAB_ENGINE:-docker}" in
    podman) command podman --remote=false "$@" ;;
    docker) command docker "$@" ;;
    *) engine_validate "$LAB_ENGINE" ;;
  esac
}

engine_available() { engine info >/dev/null 2>&1; }
engine_exec() { engine exec "$@"; }
engine_run() { engine run "$@"; }
engine_network_create() { engine network create "$@"; }
engine_network_exists() { engine network inspect "$1" >/dev/null 2>&1; }
engine_volume_exists() { engine volume inspect "$1" >/dev/null 2>&1; }
engine_volume_create() { engine volume create "$@"; }
engine_volume_remove() { engine volume rm "$@"; }
engine_image_remove() { engine image rm "$@"; }

engine_ensure_network() {
  engine_network_exists "$1" || engine_network_create "$1" || engine_network_exists "$1"
}

engine_compose() (
  if [[ "$LAB_ENGINE" == podman ]]; then
    local provider
    provider="$(command -v podman-compose)" || {
      echo "Erro: instale o provider podman-compose." >&2
      return 1
    }
    export PODMAN_COMPOSE_PROVIDER="$provider"
    # O provider executa o Podman nativo. Evita conexões remotas herdadas.
    unset CONTAINER_HOST CONTAINER_CONNECTION
  fi
  engine compose "$@"
)

engine_compose_images() {
  if [[ "$LAB_ENGINE" == podman ]]; then
    # Cada projeto gerado pelo Lab declara uma imagem explícita por serviço.
    local config
    config="$(engine_compose config)" || return
    printf '%s\n' "$config" | awk '$1 == "image:" { print $2 }'
  else
    engine_compose config --images
  fi
}

engine_socket() {
  if [[ "$LAB_ENGINE" == podman ]]; then
    printf '%s/podman/podman.sock\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  else
    printf '%s\n' /var/run/docker.sock
  fi
}

engine_require_socket() {
  [[ "$LAB_ENGINE" == podman ]] || return 0
  local socket
  socket="$(engine_socket)"
  if ! curl -fsS --max-time 5 --unix-socket "$socket" http://localhost/_ping >/dev/null; then
    printf 'Erro: API do Podman indisponível em %s. Execute systemctl --user enable --now podman.socket.\n' "$socket" >&2
    return 1
  fi
}

engine_require() {
  if [[ "$LAB_ENGINE" == podman ]]; then
    if [[ "$(lab_platform)" != linux ]] || ((EUID == 0)); then
      echo "Erro: o Lab com Podman requer Linux e um usuário sem privilégios de root." >&2
      return 1
    fi
    if ! engine_available; then
      echo "Erro: Podman rootless indisponível. Verifique podman info e os mapeamentos /etc/subuid e /etc/subgid." >&2
      return 1
    fi
  else
    lab_require_docker || return
  fi
  if ! engine_compose version >/dev/null; then
    printf 'Erro: Compose indisponível para %s.\n' "$LAB_ENGINE" >&2
    return 1
  fi
}

# Um helper de manutenção pode precisar ler dados de vários containers,
# sem alterar os rótulos SELinux dos arquivos que eles compartilham.
engine_data_run() {
  local options=()
  if [[ "$LAB_ENGINE" == podman ]]; then
    options+=(--security-opt label=disable)
  fi
  engine_run --rm "${options[@]}" "$@"
}

engine_build_cache_prune() { engine builder prune -f; }
