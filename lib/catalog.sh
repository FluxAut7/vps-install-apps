#!/usr/bin/env bash

catalog_pick_one() {
  local title="$1"
  local prompt="$2"
  local current="$3"
  shift 3

  local -a values=("$@")
  local count="${#values[@]}"
  [[ "$count" -gt 0 ]] || fail "Catalogo vazio para: $title"

  if [[ "$count" -eq 1 ]]; then
    printf '%s' "${values[0]}"
    return 0
  fi

  local -a items=()
  local value desc
  for value in "${values[@]}"; do
    desc="$prompt"
    if [[ -n "$current" && "$value" == "$current" ]]; then
      desc="$prompt • atual"
    fi
    items+=("$value" "$value||$desc")
  done

  ui_menu "$title" "${items[@]}"
}

catalog_traefik_image() {
  printf '%s' 'traefik:v3.4.0'
}

catalog_select_portainer_channel() {
  local current="${1:-$(state_get PORTAINER_CHANNEL || true)}"
  catalog_pick_one "Canal do Portainer" "Canal testado do Portainer" "$current" lts sts
}

catalog_portainer_image() {
  local channel="$1"
  case "$channel" in
    lts|sts) printf 'portainer/portainer-ce:%s' "$channel" ;;
    *) fail "Canal do Portainer invalido: $channel" ;;
  esac
}

catalog_portainer_agent_image() {
  local channel="$1"
  case "$channel" in
    lts|sts) printf 'portainer/agent:%s' "$channel" ;;
    *) fail "Canal do Portainer invalido: $channel" ;;
  esac
}