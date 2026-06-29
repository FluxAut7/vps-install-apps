#!/usr/bin/env bash

dependencies_describe() {
  local app="$1"
  case "$app" in
    postgres|redis|uptime-kuma)
      cat <<'EOF'
Dependencias:
- Base da VPS instalada: Docker, Swarm, rede interna, Traefik e Portainer
- Portainer API configurada
EOF
      ;;
    n8n)
      cat <<'EOF'
Dependencias:
- Base da VPS instalada: Docker, Swarm, rede interna, Traefik e Portainer
- Portainer API configurada
- PostgreSQL padrao: instalado automaticamente se ainda nao existir
- Redis: incluido dentro da propria stack do n8n
EOF
      ;;
    evolution-api)
      cat <<'EOF'
Dependencias:
- Base da VPS instalada: Docker, Swarm, rede interna, Traefik e Portainer
- Portainer API configurada
- PostgreSQL padrao: instalado automaticamente se ainda nao existir
- Redis: incluido dentro da propria stack da Evolution API
EOF
      ;;
    *)
      cat <<'EOF'
Dependencias:
- Base da VPS instalada: Docker, Swarm, rede interna, Traefik e Portainer
- Portainer API configurada
EOF
      ;;
  esac
}

dependencies_confirm() {
  local app="$1"
  local body
  body="$(dependencies_describe "$app")"
  ui_confirm_values "Mapa de dependencias" "$body" || return 1
}

dependencies_require_base() {
  system_require_docker

  local swarm_state
  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
  [[ "$swarm_state" == "active" ]] || fail "Docker Swarm nao esta ativo. Instale a base primeiro."

  local network_name
  network_name="$(state_get NETWORK_NAME || true)"
  [[ -n "$network_name" ]] || fail "Rede interna nao configurada. Instale a base primeiro."

  docker network inspect "$network_name" >/dev/null 2>&1 || fail "Rede interna nao encontrada: $network_name"

  portainer_require_config
}