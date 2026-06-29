#!/usr/bin/env bash

VPSI_HOME="${VPS_INSTALLER_HOME:-/opt/vps-installer}"
STATE_DIR="$VPSI_HOME/state"
APP_STATE_DIR="$STATE_DIR/apps"
STACKS_DIR="$VPSI_HOME/stacks"
BACKUP_DIR="$VPSI_HOME/backups"
LOG_DIR="$VPSI_HOME/logs"
RUN_DIR="$VPSI_HOME/run"

state_init() {
  mkdir -p "$STATE_DIR" "$APP_STATE_DIR" "$STACKS_DIR" "$BACKUP_DIR" "$LOG_DIR" "$RUN_DIR"
  chmod 700 "$VPSI_HOME" "$STATE_DIR" "$APP_STATE_DIR" "$BACKUP_DIR" "$RUN_DIR"
  touch "$STATE_DIR/config.env" "$STATE_DIR/portainer.env" "$STATE_DIR/apps.tsv"
  chmod 600 "$STATE_DIR/config.env" "$STATE_DIR/portainer.env"
}

state_env_escape() {
  printf '%q' "$1"
}

state_set() {
  local key="$1"
  local value="$2"
  local file="${3:-$STATE_DIR/config.env}"
  local tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  chmod 600 "$file" 2>/dev/null || true
  tmp="$(mktemp)"
  grep -v -E "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$(state_env_escape "$value")" >> "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
  chmod 600 "$file" 2>/dev/null || true
}

state_get() {
  local key="$1"
  local file="${2:-$STATE_DIR/config.env}"
  [[ -f "$file" ]] || return 1
  # shellcheck disable=SC1090
  . "$file"
  eval 'printf "%s" "${'"$key"':-}"'
}

state_source() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  # shellcheck disable=SC1090
  . "$file"
}

state_register_app() {
  local app_name="$1"
  local stack_name="$2"
  local app_type="$3"
  local domain="${4:-}"
  local image="${5:-}"
  local stack_file="${6:-}"

  local app_file="$APP_STATE_DIR/${app_name}.env"
  state_set APP_NAME "$app_name" "$app_file"
  state_set STACK_NAME "$stack_name" "$app_file"
  state_set APP_TYPE "$app_type" "$app_file"
  state_set APP_DOMAIN "$domain" "$app_file"
  state_set APP_IMAGE "$image" "$app_file"
  state_set STACK_FILE "$stack_file" "$app_file"
  state_set INSTALLED_AT "$(date -Iseconds)" "$app_file"

  grep -v -F "${app_name}	" "$STATE_DIR/apps.tsv" > "$RUN_DIR/apps.tsv.tmp" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' "$app_name" "$stack_name" "$app_type" "$domain" >> "$RUN_DIR/apps.tsv.tmp"
  cat "$RUN_DIR/apps.tsv.tmp" > "$STATE_DIR/apps.tsv"
  rm -f "$RUN_DIR/apps.tsv.tmp"
}

state_remove_app() {
  local app_name="$1"
  rm -f "$APP_STATE_DIR/${app_name}.env"
  grep -v -F "${app_name}	" "$STATE_DIR/apps.tsv" > "$RUN_DIR/apps.tsv.tmp" 2>/dev/null || true
  cat "$RUN_DIR/apps.tsv.tmp" > "$STATE_DIR/apps.tsv"
  rm -f "$RUN_DIR/apps.tsv.tmp"
}

state_list_apps() {
  if [[ ! -s "$STATE_DIR/apps.tsv" ]]; then
    echo "Nenhum app registrado."
    return 0
  fi
  awk -F '\t' '{ printf "- %s (%s) stack=%s domínio=%s\n", $1, $3, $2, $4 }' "$STATE_DIR/apps.tsv"
}

state_random_hex() {
  local bytes="${1:-16}"
  openssl rand -hex "$bytes"
}
