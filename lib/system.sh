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

system_service_replicas_ready() {
  awk -F'\t' '
    {
      frac = $2
      sub(/ .*/, "", frac)
      split(frac, parts, "/")
      cur = parts[1] + 0
      desired = parts[2] + 0
      if (desired > 0 && cur == desired) print $1
    }
  '
}

system_diagnose_stack() {
  local stack_name="$1"
  local fmt=$'{{.Name}}\t{{.Replicas}}'
  local services
  services="$(docker service ls --filter "label=com.docker.stack.namespace=$stack_name" --format "$fmt" 2>/dev/null)"

  if [[ -z "$services" ]]; then
    ui_warn "Nenhum serviço encontrado para a stack '$stack_name'."
    return 0
  fi

  ui_warn "Estado dos serviços de '$stack_name':"
  printf '%s\n' "$services" | awk -F'\t' '{ printf "  %s %s\n", $1, $2 }' >&2

  local name events
  while IFS=$'\t' read -r name _; do
    [[ -n "$name" ]] || continue
    events="$(docker service ps --no-trunc --format '{{.CurrentState}}|{{.Error}}' "$name" 2>/dev/null | head -5)"
    [[ -n "$events" ]] || continue
    ui_warn "Últimos eventos de $name:"
    printf '%s\n' "$events" | awk -F'|' '{ if ($2 != "") printf "    %s - erro: %s\n", $1, $2; else printf "    %s\n", $1 }' >&2
  done <<< "$services"

  ui_hint "Logs completos: docker service logs <serviço>"
}

system_wait_stack() {
  local stack_name="$1"
  local timeout="${2:-300}"
  local grace=30
  local elapsed=0
  local fmt=$'{{.Name}}\t{{.Replicas}}'

  ui_info "Aguardando serviços de $stack_name ficarem online..."

  while (( elapsed < grace )); do
    if [[ -n "$(docker service ls --filter "label=com.docker.stack.namespace=$stack_name" --format "$fmt" 2>/dev/null)" ]]; then
      break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  local last_ready=-1 lines total ready
  elapsed=0
  while (( elapsed < timeout )); do
    lines="$(docker service ls --filter "label=com.docker.stack.namespace=$stack_name" --format "$fmt" 2>/dev/null)"
    if [[ -n "$lines" ]]; then
      total="$(printf '%s\n' "$lines" | wc -l)"
      ready="$(printf '%s\n' "$lines" | system_service_replicas_ready | wc -l)"

      if (( ready != last_ready )); then
        ui_info "Serviços prontos: $ready de $total ($stack_name)"
        last_ready=$ready
      fi

      if (( ready == total )); then
        ui_success "Serviços convergidos para $stack_name."
        return 0
      fi
    fi

    sleep 5
    elapsed=$((elapsed + 5))
  done

  ui_warn "Timeout aguardando $stack_name convergir."
  system_diagnose_stack "$stack_name"
  return 1
}

system_wait_https() {
  local domain="$1"
  local timeout="${2:-120}"
  local elapsed=0
  local tls_error_seen=0
  local code exit_code

  ui_info "Verificando resposta HTTPS de $domain..."

  while (( elapsed < timeout )); do
    code="$(curl -sS -o /dev/null --max-time 8 -w '%{http_code}' "https://$domain" 2>/dev/null)"
    exit_code=$?

    if [[ "$exit_code" -eq 0 && "$code" -ge 200 && "$code" -lt 500 ]]; then
      ui_success "HTTPS respondeu em $domain (código $code)."
      return 0
    fi

    [[ "$exit_code" -eq 60 ]] && tls_error_seen=1

    sleep 10
    elapsed=$((elapsed + 10))
  done

  if [[ "$tls_error_seen" -eq 1 ]]; then
    ui_warn "Timeout aguardando HTTPS em $domain: certificado ainda não foi emitido (erro de TLS)."
  else
    ui_warn "Timeout aguardando HTTPS em $domain: serviço não respondeu (conexão recusada ou DNS incorreto)."
  fi
  ui_hint "Verifique a emissão do certificado: docker service logs traefik_traefik --tail 50 | grep -i acme"
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
  local mem_values used total
  mem_values="$(awk '
    /MemTotal:/ { total = $2 / 1024 }
    /MemAvailable:/ { available = $2 / 1024 }
    END {
      if (available == "") available = 0
      used = total - available
      if (used < 0) used = 0
      printf "%.0f %.0f", used, total
    }
  ' /proc/meminfo)"

  used="${mem_values%% *}"
  total="${mem_values##* }"
  printf '%s / %s' "$(system_format_mib "$used")" "$(system_format_mib "$total")"
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

  docker ps --format '{{.ID}}|{{.Label "com.docker.stack.namespace"}}' > "$ps_file"
  if [[ ! -s "$ps_file" ]]; then
    rm -f "$ps_file" "$stats_file"
    return 0
  fi

  docker stats --no-stream --format '{{.ID}}|{{.CPUPerc}}|{{.MemUsage}}' > "$stats_file"

  awk -F '|' '
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