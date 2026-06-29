#!/usr/bin/env bash

system_require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    fail "Execute como root ou via sudo."
  fi
}

system_detect_os() {
  [[ -f /etc/os-release ]] || fail "Nao foi possivel detectar o sistema operacional."
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
      fail "Sistema nao suportado: ${PRETTY_NAME:-desconhecido}"
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
  command -v docker >/dev/null 2>&1 || fail "Docker nao instalado. Instale a base primeiro."
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

  ui_info "Aguardando servicos de $service_prefix ficarem online..."
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
