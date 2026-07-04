#!/usr/bin/env bash
# A descrição de dependências por app agora vem do manifesto
# (appdef_dependencies_text, em lib/appdef.sh). Aqui fica só a checagem da base.

dependencies_require_base() {
  system_require_docker

  local swarm_state
  swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
  [[ "$swarm_state" == "active" ]] || fail "Docker Swarm não está ativo. Instale a base primeiro."

  local network_name
  network_name="$(state_get NETWORK_NAME || true)"
  [[ -n "$network_name" ]] || fail "Rede interna não configurada. Instale a base primeiro."

  docker network inspect "$network_name" >/dev/null 2>&1 || fail "Rede interna não encontrada: $network_name"

  portainer_require_config
}