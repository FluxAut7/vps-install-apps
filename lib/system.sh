#!/usr/bin/env bash

system_require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    fail "Execute como root ou via sudo."
  fi
}

system_detect_os() {
  [[ -f /etc/os-release ]] || fail "Não foi possível detectar o sistema operacional."
  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
    ubuntu)
      [[ "${VERSION_ID:-}" == "22.04" || "${VERSION_ID:-}" == "24.04" ]] || fail "Ubuntu suportado: 22.04 ou 24.04."
      ;;
    debian)
      [[ "${VERSION_ID:-}" == "12" ]] || fail "Debian suportado: 12."
      ;;
    *)
      fail "Sistema não suportado: ${PRETTY_NAME:-desconhecido}"
      ;;
  esac

  export VPSI_OS_ID="$ID"
  export VPSI_OS_VERSION="$VERSION_ID"
  export VPSI_OS_CODENAME="${VERSION_CODENAME:-}"
}

system_apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

system_install_base_packages() {
  ui_info "Verificando dependencias basicas..."
  apt-get update -y >/dev/null
  system_apt_install ca-certificates curl gnupg lsb-release jq openssl dialog apache2-utils tar gzip >/dev/null
}

system_install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ui_success "Docker ja instalado."
    return 0
  fi

  ui_info "Instalando Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${VPSI_OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  local arch
  arch="$(dpkg --print-architecture)"
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${VPSI_OS_ID} ${VPSI_OS_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y >/dev/null
  system_apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  systemctl enable --now docker >/dev/null
  ui_success "Docker instalado."
}

system_require_docker() {
  command -v docker >/dev/null 2>&1 || fail "Docker não instalado. Instale a base primeiro."
}

system_init_swarm() {
  system_require_docker
  local state
  state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then
    ui_success "Docker Swarm ja ativo."
    return 0
  fi

  local advertise_addr
  advertise_addr="$(hostname -I | awk '{print $1}')"
  [[ -n "$advertise_addr" ]] || advertise_addr="127.0.0.1"
  docker swarm init --advertise-addr "$advertise_addr" >/dev/null
  ui_success "Docker Swarm iniciado."
}

system_ensure_network() {
  local network_name="$1"
  if docker network inspect "$network_name" >/dev/null 2>&1; then
    ui_success "Rede ja existe: $network_name"
    return 0
  fi
  docker network create --driver=overlay --attachable "$network_name" >/dev/null
  ui_success "Rede criada: $network_name"
}

system_wait_stack() {
  local service_prefix="$1"
  local timeout="${2:-180}"
  local elapsed=0

  ui_info "Aguardando serviços de $service_prefix ficarem online..."
  while (( elapsed < timeout )); do
    if docker service ls --format '{{.Name}} {{.Replicas}}' | awk -v p="$service_prefix" '$1 ~ "^"p"_" && $2 !~ /^0\// { ok=1 } END { exit ok ? 0 : 1 }'; then
      ui_success "Servicos detectados para $service_prefix."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  ui_warn "Timeout aguardando $service_prefix. Verifique com: docker service ls"
  return 1
}

system_cpu_usage_pct() {
  local user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2
  read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 _ < /proc/stat
  sleep 0.2
  read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ < /proc/stat

  local total1 total2 idle_total1 idle_total2 total_diff idle_diff
  total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1))
  total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
  idle_total1=$((idle1 + iowait1))
  idle_total2=$((idle2 + iowait2))
  total_diff=$((total2 - total1))
  idle_diff=$((idle_total2 - idle_total1))

  if (( total_diff <= 0 )); then
    printf '0.0'
    return 0
  fi

  awk -v total="$total_diff" -v idle="$idle_diff" 'BEGIN { printf "%.1f", ((total - idle) / total) * 100 }'
}

system_format_mib() {
  local mib="$1"
  awk -v v="$mib" 'BEGIN {
    if (v >= 1024) {
      printf "%.1f GiB", v / 1024
    } else {
      printf "%.0f MiB", v
    }
  }'
}

system_memory_usage_line() {
  awk '
    /MemTotal:/ { total = $2 / 1024 }
    /MemAvailable:/ { available = $2 / 1024 }
    END {
      used = total - available
      if (used < 0) used = 0
      printf "%s / %s", used, total
    }
  ' /proc/meminfo | while IFS='/' read -r used total; do
    used="${used// /}"
    total="${total// /}"
    printf '%s / %s' "$(system_format_mib "$used")" "$(system_format_mib "$total")"
  done
}

system_disk_usage_line() {
  df -P -B1 / | awk 'NR==2 {
    used = $3 / 1073741824
    total = $2 / 1073741824
    printf "%.1f GiB / %.1f GiB (%s)", used, total, $5
  }'
}

system_vps_usage_line() {
  local cpu memory disk
  cpu="$(system_cpu_usage_pct)"
  memory="$(system_memory_usage_line)"
  disk="$(system_disk_usage_line)"
  printf 'CPU %s%% | RAM %s | Disco %s' "$cpu" "$memory" "$disk"
}

system_collect_stack_usage() {
  system_require_docker

  local ps_file stats_file
  ps_file="$(mktemp "$RUN_DIR/stack-ps.XXXXXX")"
  stats_file="$(mktemp "$RUN_DIR/stack-stats.XXXXXX")"

  docker ps --format '{{.ID}}	{{.Label "com.docker.stack.namespace"}}' > "$ps_file"
  if [[ ! -s "$ps_file" ]]; then
    rm -f "$ps_file" "$stats_file"
    return 0
  fi

  docker stats --no-stream --format '{{.ID}}	{{.CPUPerc}}	{{.MemUsage}}' > "$stats_file"

  awk -F '\t' '
    function mem_to_mib(text, parts, raw) {
      gsub(/ /, "", text)
      split(text, parts, "/")
      raw = parts[1]
      if (raw == "" || raw == "0B") return 0
      if (raw ~ /GiB$/) { sub(/GiB$/, "", raw); return (raw + 0) * 1024 }
      if (raw ~ /MiB$/) { sub(/MiB$/, "", raw); return raw + 0 }
      if (raw ~ /KiB$/) { sub(/KiB$/, "", raw); return (raw + 0) / 1024 }
      if (raw ~ /B$/) { sub(/B$/, "", raw); return (raw + 0) / 1048576 }
      return raw + 0
    }
    NR == FNR {
      if ($2 != "") stack[$1] = $2
      next
    }
    {
      if (!($1 in stack)) next
      cpu = $2
      gsub(/%/, "", cpu)
      name = stack[$1]
      containers[name] += 1
      cpu_sum[name] += cpu + 0
      mem_sum[name] += mem_to_mib($3)
    }
    END {
      for (name in containers) {
        printf "%s\t%d\t%.1f\t%.1f\n", name, containers[name], cpu_sum[name], mem_sum[name]
      }
    }
  ' "$ps_file" "$stats_file"

  rm -f "$ps_file" "$stats_file"
}

system_upgrade_packages_interactive() {
  ui_clear
  ui_title "Atualizar pacotes da VPS"
  ui_warn "Esta ação executa apt-get update e apt-get upgrade -y. Pode demorar e reiniciar serviços durante atualizações."

  if ! ui_confirm "Deseja continuar com a atualização dos pacotes da VPS?"; then
    ui_warn "Atualização cancelada."
    ui_pause
    return 0
  fi

  ui_info "Atualizando índice de pacotes..."
  apt-get update -y

  ui_info "Atualizando pacotes instalados..."
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  ui_success "Atualização de pacotes concluída."
  ui_pause
}