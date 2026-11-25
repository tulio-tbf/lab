# Diagnóstico de hardware para os serviços de IA do lab (Ollama e afins).
# Carregado com `source` depois de lib/platform.sh; não execute diretamente.
# Compatível com o Bash 3.2 do macOS: sem arrays associativos nem ${var,,}.
#
# Variáveis preenchidas por lab_hw_detect (memória em MB):
#   HW_PLATFORM HW_ARCH HW_APPLE_SILICON HW_CPU_NAME HW_CPU_CORES HW_AVX2
#   HW_HOST_RAM_MB HW_DOCKER_DESKTOP HW_DOCKER_MEM_MB HW_DOCKER_CPUS
#   HW_NVIDIA_GPU HW_GPU_NAME HW_GPU_VRAM_MB HW_DOCKER_GPU HW_DISK_FREE_MB

# Memória típica (MB) de cada serviço do lab em uso leve. Serve para estimar
# quanto reservar ao Docker; não é limite rígido.
lab_service_memory_mb() {
  case "$1" in
    traefik) echo 64 ;;
    wordpress) echo 256 ;;
    wordpress-db) echo 512 ;;
    mautic) echo 512 ;;
    mautic-db) echo 384 ;;
    n8n) echo 512 ;;
    redis) echo 64 ;;
    minio) echo 256 ;;
    portainer) echo 64 ;;
    adminer) echo 32 ;;
    pgadmin) echo 256 ;;
    mailhog) echo 32 ;;
    evolution-db) echo 256 ;;
    evolution-api) echo 384 ;;
    qdrant) echo 512 ;;
    open-webui) echo 768 ;;
    searxng) echo 256 ;;
    # O consumo do Ollama depende do modelo e é somado à parte.
    ollama) echo 256 ;;
    *) echo 128 ;;
  esac
}

# Memória aproximada (MB) que o modelo ocupa carregado, com quantização Q4 e
# contexto padrão. Inclui o modelo de embedding, que fica carregado junto.
lab_model_memory_mb() {
  case "$1" in
    *:1.7b) echo 2000 ;;
    *:4b) echo 3500 ;;
    *:8b) echo 6000 ;;
    *:14b) echo 10500 ;;
    *) echo 6000 ;;
  esac
}

# Converte MB em GB com uma casa decimal.
_hw_gb() {
  awk -v mb="$1" 'BEGIN { printf "%.1f", mb / 1024 }'
}

_hw_trim() {
  tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

_hw_nvidia_smi() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi "$@"
  elif [[ -x /usr/lib/wsl/lib/nvidia-smi ]]; then
    /usr/lib/wsl/lib/nvidia-smi "$@"
  elif command -v nvidia-smi.exe >/dev/null 2>&1; then
    nvidia-smi.exe "$@"
  else
    return 127
  fi
}

lab_hw_detect() {
  local disk_path="${1:-$HOME}"
  local bytes value runtimes

  HW_PLATFORM="$(lab_platform)"
  HW_ARCH="$(uname -m)"
  HW_APPLE_SILICON=0
  HW_CPU_NAME="desconhecido"
  HW_CPU_CORES=0
  HW_AVX2=0
  HW_HOST_RAM_MB=0

  case "$HW_PLATFORM" in
    macos)
      # hw.optional.arm64 também vale 1 sob Rosetta; uname -m não.
      if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
        HW_APPLE_SILICON=1
        HW_ARCH="arm64"
      fi
      HW_CPU_NAME="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo desconhecido)"
      HW_CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
      bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
      HW_HOST_RAM_MB=$((bytes / 1048576))
      if sysctl -n machdep.cpu.leaf7_features 2>/dev/null | grep -qw AVX2; then
        HW_AVX2=1
      fi
      ;;
    *)
      if [[ -r /proc/cpuinfo ]]; then
        HW_CPU_NAME="$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
        grep -qw avx2 /proc/cpuinfo && HW_AVX2=1
      fi
      HW_CPU_CORES="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)"
      if [[ -r /proc/meminfo ]]; then
        HW_HOST_RAM_MB="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)"
      fi
      # No WSL e no Git Bash, /proc/meminfo mostra só a VM; a RAM física do
      # Windows vem do PowerShell.
      if [[ "$HW_PLATFORM" == "wsl" || "$HW_PLATFORM" == "gitbash" ]] && command -v powershell.exe >/dev/null 2>&1; then
        bytes="$(powershell.exe -NoProfile -Command '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory' 2>/dev/null | _hw_trim || true)"
        if [[ "$bytes" =~ ^[0-9]+$ ]]; then
          HW_HOST_RAM_MB=$((bytes / 1048576))
        fi
      fi
      ;;
  esac
  [[ -n "$HW_CPU_NAME" ]] || HW_CPU_NAME="desconhecido"

  HW_DOCKER_DESKTOP=0
  HW_DOCKER_MEM_MB=0
  HW_DOCKER_CPUS=0
  runtimes=""
  if [[ "$LAB_ENGINE" == podman ]]; then
    HW_DOCKER_MEM_MB="$HW_HOST_RAM_MB"
    HW_DOCKER_CPUS="$HW_CPU_CORES"
  elif engine_available; then
    case "$(engine info --format '{{.OperatingSystem}}' 2>/dev/null)" in
      *"Docker Desktop"*) HW_DOCKER_DESKTOP=1 ;;
    esac
    bytes="$(engine info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
    [[ "$bytes" =~ ^[0-9]+$ ]] && HW_DOCKER_MEM_MB=$((bytes / 1048576))
    HW_DOCKER_CPUS="$(engine info --format '{{.NCPU}}' 2>/dev/null || echo 0)"
    runtimes="$(engine info --format '{{range $name, $_ := .Runtimes}}{{$name}} {{end}}' 2>/dev/null || true)"
  fi

  HW_NVIDIA_GPU=0
  HW_GPU_NAME=""
  HW_GPU_VRAM_MB=0
  HW_DOCKER_GPU=0
  if [[ "$HW_PLATFORM" != "macos" ]]; then
    value="$(_hw_nvidia_smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | _hw_trim || true)"
    if [[ -n "$value" ]]; then
      HW_NVIDIA_GPU=1
      HW_GPU_NAME="${value%,*}"
      HW_GPU_VRAM_MB="$(printf '%s' "${value##*,}" | _hw_trim)"
      [[ "$HW_GPU_VRAM_MB" =~ ^[0-9]+$ ]] || HW_GPU_VRAM_MB=0
      # Docker Desktop (backend WSL 2) repassa a GPU NVIDIA sem configuração
      # extra; o Engine nativo precisa do NVIDIA Container Toolkit.
      if ((HW_DOCKER_DESKTOP)) || [[ " $runtimes " == *" nvidia "* ]]; then
        HW_DOCKER_GPU=1
      fi
    fi
  fi

  HW_DISK_FREE_MB="$(df -Pk "$disk_path" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }')"
  [[ -n "$HW_DISK_FREE_MB" ]] || HW_DISK_FREE_MB=0
}

# Escolhe o modo do Ollama:
#   native     roda no sistema hospedeiro, fora do Docker
#   docker     container só com CPU
#   docker-gpu container com GPU NVIDIA
# Imprime "modo|motivo".
lab_ollama_recommend_mode() {
  if [[ "$HW_PLATFORM" == "macos" ]]; then
    if ((HW_APPLE_SILICON)); then
      echo "native|No Mac, containers não acessam a GPU; o Ollama nativo usa Metal no Apple Silicon e é várias vezes mais rápido."
    else
      echo "native|Mac Intel: não há aceleração por GPU no Docker nem no Ollama; rodar nativo evita dividir a RAM com a VM do Docker Desktop."
    fi
    return
  fi

  if ((HW_NVIDIA_GPU)); then
    if ((HW_DOCKER_GPU)); then
      echo "docker-gpu|GPU NVIDIA acessível pelo Docker; o container roda com aceleração."
    else
      echo "native|GPU NVIDIA detectada; o Ollama nativo pode usar a GPU diretamente."
    fi
    return
  fi

  echo "docker|Sem GPU NVIDIA: o Ollama roda só na CPU, e no Linux/WSL o container tem desempenho igual ao nativo."
}

# Memória (MB) disponível para o modelo no modo informado, já descontando o
# sistema operacional e os demais serviços do lab.
lab_model_budget_mb() {
  local mode="$1"
  local services_mb="$2"
  local os_reserve=4096
  local budget

  case "$mode" in
    docker-gpu)
      budget=$((HW_GPU_VRAM_MB - 512))
      ;;
    docker)
      # O modelo divide a VM do Docker com os outros containers.
      budget=$((HW_DOCKER_MEM_MB - services_mb))
      ;;
    native)
      # O Docker Desktop reserva para a VM toda a memória configurada, mesmo
      # sem uso; no Engine nativo só conta o que os containers consomem.
      if ((HW_DOCKER_DESKTOP)) && ((HW_DOCKER_MEM_MB > services_mb)); then
        services_mb="$HW_DOCKER_MEM_MB"
      fi
      if ((HW_NVIDIA_GPU)); then
        budget=$((HW_GPU_VRAM_MB - 512))
      elif ((HW_APPLE_SILICON)); then
        # Memória unificada: o macOS libera ~70% da RAM para a GPU.
        budget=$((HW_HOST_RAM_MB * 7 / 10 - services_mb))
      else
        budget=$((HW_HOST_RAM_MB - os_reserve - services_mb))
      fi
      ;;
    *)
      budget=0
      ;;
  esac
  ((budget < 0)) && budget=0
  echo "$budget"
}

# Escolhe o maior modelo que cabe no orçamento. Em CPU sem GPU, limita a 4B:
# um 8B funciona, mas gera poucos tokens por segundo e trava fluxos de agente.
lab_recommend_model() {
  local budget_mb="$1"
  local accelerated="$2"
  local model

  if ((budget_mb >= 10500)); then
    model="qwen3:14b"
  elif ((budget_mb >= 6000)); then
    model="qwen3:8b"
  elif ((budget_mb >= 3500)); then
    model="qwen3:4b"
  else
    model="qwen3:1.7b"
  fi

  if ((!accelerated)); then
    case "$model" in
      qwen3:14b|qwen3:8b) model="qwen3:4b" ;;
    esac
  fi
  echo "$model"
}

# Imprime o relatório e define HW_OLLAMA_MODE, HW_LLM_MODEL e HW_WARNINGS
# (quantidade de alertas). Argumentos: modo pedido (auto|native|docker|
# docker-gpu|remote) e a soma de memória dos serviços selecionados.
lab_hw_report() {
  local requested_mode="$1"
  local services_mb="$2"
  local wants_ollama="$3"
  local recommendation reason mode budget accelerated docker_needed
  local suggested_docker_mb host_needed

  HW_WARNINGS=0
  recommendation="$(lab_ollama_recommend_mode)"
  reason="${recommendation#*|}"
  mode="${recommendation%%|*}"
  if [[ "$requested_mode" != "auto" ]]; then
    mode="$requested_mode"
    reason="modo definido por --ollama-mode."
  fi
  HW_OLLAMA_MODE="$mode"

  printf '\n=== Diagnóstico de hardware ===\n'
  printf 'Plataforma:    %s (%s)\n' "$HW_PLATFORM" "$HW_ARCH"
  printf 'CPU:           %s, %s núcleos, AVX2: %s\n' "$HW_CPU_NAME" "$HW_CPU_CORES" "$([[ $HW_AVX2 == 1 ]] && echo sim || echo não)"
  printf 'RAM física:    %s GB\n' "$(_hw_gb "$HW_HOST_RAM_MB")"
  if ((HW_DOCKER_MEM_MB)); then
    printf 'Engine:        %s, %s GB de RAM, %s CPUs\n' \
      "$LAB_ENGINE" \
      "$(_hw_gb "$HW_DOCKER_MEM_MB")" "$HW_DOCKER_CPUS"
  else
    printf 'Engine:        %s indisponível\n' "$LAB_ENGINE"
  fi
  if ((HW_APPLE_SILICON)); then
    printf 'GPU:           Apple Silicon (Metal, só fora do Docker)\n'
  elif ((HW_NVIDIA_GPU)); then
    printf 'GPU:           %s, %s GB VRAM, acessível pelo engine: %s\n' "$HW_GPU_NAME" "$(_hw_gb "$HW_GPU_VRAM_MB")" "$([[ $HW_DOCKER_GPU == 1 ]] && echo sim || echo não)"
  else
    printf 'GPU:           nenhuma GPU utilizável para LLM\n'
  fi
  printf 'Disco livre:   %s GB em %s\n' "$(_hw_gb "$HW_DISK_FREE_MB")" "$DATA"

  docker_needed=$((services_mb + services_mb / 4))
  printf '\nServiços selecionados usam ~%s GB (com 25%% de folga).\n' "$(_hw_gb "$docker_needed")"

  if ((wants_ollama)); then
    printf '\nOllama: modo recomendado = %s\n  %s\n' "$(lab_ollama_recommend_mode | cut -d'|' -f1)" "$(lab_ollama_recommend_mode | cut -d'|' -f2)"
    if [[ "$requested_mode" != "auto" ]]; then
      printf 'Ollama: modo escolhido = %s\n' "$mode"
    fi

    if [[ "$mode" == "remote" ]]; then
      HW_LLM_MODEL="${LAB_LLM_MODEL:-qwen3:8b}"
      printf '  Modelos rodam em %s; escolha-os conforme o hardware daquela máquina.\n' "$OLLAMA_URL"
    else
      budget="$(lab_model_budget_mb "$mode" "$docker_needed")"
      accelerated=0
      if [[ "$mode" == "docker-gpu" ]] || { [[ "$mode" == "native" ]] && ((HW_APPLE_SILICON || HW_NVIDIA_GPU)); }; then
        accelerated=1
      fi
      HW_LLM_MODEL="${LAB_LLM_MODEL:-$(lab_recommend_model "$budget" "$accelerated")}"
      printf '  Memória livre para o modelo: ~%s GB\n' "$(_hw_gb "$budget")"
      printf '  Modelo recomendado: %s (+ nomic-embed-text para RAG)\n' "$HW_LLM_MODEL"
      if ((!accelerated)); then
        printf '  Sem GPU, espere poucos tokens/s; modelos de 8B+ ficam lentos demais para agentes.\n'
      fi
      if ((!HW_AVX2)) && ((!accelerated)); then
        printf '  Alerta: CPU sem AVX2; a inferência em CPU será muito lenta.\n'
        HW_WARNINGS=$((HW_WARNINGS + 1))
      fi
      if ((budget < 2000)); then
        printf '  Alerta: não sobra memória nem para o menor modelo. Reduza os serviços, aumente a RAM disponível ou use --ollama-mode remote.\n'
        HW_WARNINGS=$((HW_WARNINGS + 1))
      fi
      if [[ "$mode" == "docker" ]]; then
        docker_needed=$((docker_needed + $(lab_model_memory_mb "$HW_LLM_MODEL")))
      fi
      if ((HW_DISK_FREE_MB < 20480)); then
        printf '  Alerta: menos de 20 GB livres; cada modelo ocupa de 1 a 9 GB em disco.\n'
        HW_WARNINGS=$((HW_WARNINGS + 1))
      fi
    fi
  fi

  suggested_docker_mb=$(( (docker_needed + 1023) / 1024 * 1024 ))
  ((suggested_docker_mb < 4096)) && suggested_docker_mb=4096
  printf '\nMemória recomendada para os containers: %s GB' "$((suggested_docker_mb / 1024))"
  if ((HW_DOCKER_MEM_MB)); then
    printf ' (atual: %s GB)' "$(_hw_gb "$HW_DOCKER_MEM_MB")"
  fi
  printf '\n'

  # 512 MB de tolerância: o Docker informa um pouco menos que o configurado.
  if ((HW_DOCKER_MEM_MB)) && ((HW_DOCKER_MEM_MB + 512 < suggested_docker_mb)); then
    HW_WARNINGS=$((HW_WARNINGS + 1))
    case "$HW_PLATFORM" in
      macos) printf '  Ajuste em Docker Desktop > Settings > Resources > Memory.\n' ;;
      wsl|gitbash)
        printf '  Ajuste em %%UserProfile%%\\.wslconfig e execute "wsl --shutdown":\n'
        printf '    [wsl2]\n    memory=%sGB\n' "$((suggested_docker_mb / 1024))"
        ;;
      *) printf '  O engine usa a RAM do Linux; feche outros programas ou reduza os serviços.\n' ;;
    esac
  fi

  # Com o Ollama fora do Docker, a RAM reservada a mais para a VM do Docker
  # Desktop fica parada enquanto falta para o modelo.
  if ((wants_ollama)) && [[ "$mode" == "native" ]] && ((HW_DOCKER_DESKTOP)) && ((!HW_NVIDIA_GPU)) \
    && ((HW_DOCKER_MEM_MB > suggested_docker_mb + 1024)); then
    printf '  Dica: reduzir o Docker para %s GB libera ~%s GB para o modelo nativo.\n' \
      "$((suggested_docker_mb / 1024))" "$(_hw_gb $((HW_DOCKER_MEM_MB - suggested_docker_mb)))"
  fi

  host_needed=$((suggested_docker_mb + 4096))
  if ((HW_DOCKER_DESKTOP)) && ((HW_DOCKER_MEM_MB > suggested_docker_mb)); then
    host_needed=$((HW_DOCKER_MEM_MB + 4096))
  fi
  if ((wants_ollama)) && [[ "$mode" == "native" ]] && ((!HW_NVIDIA_GPU)); then
    host_needed=$((host_needed + $(lab_model_memory_mb "$HW_LLM_MODEL")))
  fi
  if ((HW_HOST_RAM_MB)) && ((host_needed > HW_HOST_RAM_MB)); then
    HW_WARNINGS=$((HW_WARNINGS + 1))
    printf '  Alerta: Containers + modelo + sistema pedem ~%s GB, mas a máquina tem %s GB.\n' "$(_hw_gb "$host_needed")" "$(_hw_gb "$HW_HOST_RAM_MB")"
    printf '  Selecione menos serviços, use um modelo menor ou rode o Ollama em outra máquina (--ollama-mode remote).\n'
  fi
  printf '\n'
}
