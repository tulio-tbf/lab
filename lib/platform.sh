# Funções compartilhadas pelos scripts do lab para macOS, WSL, Linux e Git Bash.
# Este arquivo é carregado com `source`; não execute diretamente.

lab_platform() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo gitbash ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    *) echo linux ;;
  esac
}

lab_require_docker() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  case "$(lab_platform)" in
    macos)
      echo "Erro: o Docker não está acessível neste Mac." >&2
      echo "Abra o Docker Desktop e aguarde o status 'Engine running' antes de continuar." >&2
      ;;
    wsl)
      echo "Erro: o Docker Engine não está acessível neste WSL." >&2
      echo "Com Engine nativo, inicie o systemd e o serviço Docker antes de continuar:" >&2
      echo "  systemctl is-system-running" >&2
      echo "  sudo systemctl start docker" >&2
      echo "Se o WSL não usar systemd, habilite [boot] systemd=true em /etc/wsl.conf e execute 'wsl --shutdown' no PowerShell." >&2
      echo "Com Docker Desktop, habilite esta distribuição em Settings > Resources > WSL Integration." >&2
      ;;
    gitbash)
      echo "Erro: o Docker não está acessível." >&2
      echo "Abra o Docker Desktop e aguarde o status 'Engine running' antes de continuar." >&2
      ;;
    *)
      echo "Erro: o Docker Engine não está acessível." >&2
      echo "Inicie o serviço antes de continuar: sudo systemctl start docker" >&2
      ;;
  esac
  return 1
}

# Origem do socket do agente SSH montado nos containers. No macOS, o Docker
# Desktop não consegue montar o socket do launchd; ele expõe o agente do host
# dentro da VM em /run/host-services/ssh-auth.sock.
lab_ssh_agent_mount_source() {
  if [[ "$(lab_platform)" == "macos" ]]; then
    printf '%s\n' '/run/host-services/ssh-auth.sock'
  else
    printf '%s\n' '${SSH_AUTH_SOCK:-/dev/null}'
  fi
}

lab_check_ssh_agent() {
  local context="${1:-nos containers}"

  if [[ "$(lab_platform)" == "macos" ]]; then
    if ssh-add -l >/dev/null 2>&1; then
      echo "Agente SSH disponível para os containers de aplicação."
    else
      echo "Aviso: nenhuma chave carregada no agente SSH; Git por SSH ficará indisponível $context." >&2
      echo "Carregue a chave com 'ssh-add --apple-use-keychain ~/.ssh/id_ed25519'." >&2
    fi
    return 0
  fi

  if [[ -z "${SSH_AUTH_SOCK:-}" && -S "$HOME/.ssh/docker-lab-agent.sock" ]]; then
    SSH_AUTH_SOCK="$HOME/.ssh/docker-lab-agent.sock"
    export SSH_AUTH_SOCK
  fi

  if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then
    echo "Agente SSH disponível para os containers de aplicação."
  else
    echo "Aviso: agente SSH não encontrado; Git por SSH ficará indisponível $context." >&2
    echo "Carregue a chave com ssh-add e inicie os containers novamente." >&2
  fi
}
