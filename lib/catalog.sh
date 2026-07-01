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

catalog_select_n8n_version() {
  local current="${1:-2.11.3}"
  local csv="${VPSI_TESTED_N8N_VERSIONS:-2.11.3}"
  local -a values=()
  IFS=',' read -r -a values <<< "$csv"
  catalog_pick_one "Versao testada do n8n" "Versao testada disponivel no catalogo" "$current" "${values[@]}"
}

catalog_n8n_image() {
  printf 'n8nio/n8n:%s' "$1"
}

catalog_n8n_runners_image() {
  printf 'n8nio/runners:%s' "$1"
}

catalog_select_uptime_kuma_major() {
  local current="${1:-1}"
  catalog_pick_one "Versao do Uptime Kuma" "Versao testada do Uptime Kuma" "$current" 1 2
}

catalog_uptime_kuma_image() {
  local major="$1"
  case "$major" in
    1|2) printf 'louislam/uptime-kuma:%s' "$major" ;;
    *) fail "Versao do Uptime Kuma invalida: $major" ;;
  esac
}

catalog_select_postgres_tag() {
  local current="${1:-16-alpine}"
  local csv="${VPSI_TESTED_POSTGRES_VERSIONS:-16-alpine}"
  local -a values=()
  IFS=',' read -r -a values <<< "$csv"
  catalog_pick_one "Versao do PostgreSQL" "Tag testada do PostgreSQL" "$current" "${values[@]}"
}

catalog_postgres_image() {
  printf 'postgres:%s' "$1"
}

catalog_select_redis_tag() {
  local current="${1:-7-alpine}"
  local csv="${VPSI_TESTED_REDIS_VERSIONS:-7-alpine}"
  local -a values=()
  IFS=',' read -r -a values <<< "$csv"
  catalog_pick_one "Versao do Redis" "Tag testada do Redis" "$current" "${values[@]}"
}

catalog_redis_image() {
  printf 'redis:%s' "$1"
}

catalog_select_evolution_tag() {
  local current="${1:-latest}"
  local csv="${VPSI_TESTED_EVOLUTION_VERSIONS:-latest}"
  local -a values=()
  IFS=',' read -r -a values <<< "$csv"
  catalog_pick_one "Versao da Evolution API" "Tag testada da Evolution API" "$current" "${values[@]}"
}

catalog_evolution_image() {
  printf 'evoapicloud/evolution-api:%s' "$1"
}