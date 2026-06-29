#!/usr/bin/env bash

ui_clear() {
  clear 2>/dev/null || true
}

ui_title() {
  local title="$1"
  printf '\033[1;33m============================================================\033[0m\n' >&2
  printf '\033[1;97m%s\033[0m\n' "$title" >&2
  printf '\033[1;33m============================================================\033[0m\n' >&2
}

ui_info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2
}

ui_success() {
  printf '\033[1;32m[OK]\033[0m %s\n' "$*" >&2
}

ui_warn() {
  printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2
}

ui_error() {
  printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2
}

fail() {
  ui_error "$*"
  exit 1
}

ui_pause() {
  echo >&2
  printf 'Pressione Enter para continuar...' >&2
  read -r _
}

ui_has_dialog() {
  command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 2 ]]
}

ui_menu() {
  local title="$1"
  shift

  if ui_has_dialog; then
    local result
    result="$(dialog --clear --stdout --title "$title" --menu "Escolha uma opção:" 22 78 14 "$@")" || true
    printf '%s' "$result"
    return 0
  fi

  printf '%s\n\n' "$title" >&2
  local args=("$@")
  local i
  for ((i=0; i<${#args[@]}; i+=2)); do
    printf '  [%s] %s\n' "${args[$i]}" "${args[$((i+1))]}" >&2
  done
  echo >&2
  local choice
  printf 'Opção: ' >&2
  read -r choice
  printf '%s' "$choice"
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"

  if ui_has_dialog; then
    dialog --clear --stdout --inputbox "$prompt" 10 78 "$default" || true
    return 0
  fi

  local value
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
    read -r value
    printf '%s' "${value:-$default}"
  else
    printf '%s: ' "$prompt" >&2
    read -r value
    printf '%s' "$value"
  fi
}

ui_password() {
  local prompt="$1"

  if ui_has_dialog; then
    dialog --clear --stdout --passwordbox "$prompt" 10 78 || true
    return 0
  fi

  local value
  printf '%s: ' "$prompt" >&2
  read -r -s value
  echo >&2
  printf '%s' "$value"
}

ui_confirm() {
  local prompt="$1"

  if ui_has_dialog; then
    dialog --clear --yesno "$prompt" 10 78
    return $?
  fi

  local answer
  printf '%s (S/N): ' "$prompt" >&2
  read -r answer
  [[ "$answer" =~ ^[SsYy]$ ]]
}

ui_confirm_values() {
  local title="$1"
  local body="$2"

  if ui_has_dialog; then
    dialog --clear --yesno "$body" 18 78
    return $?
  fi

  ui_title "$title"
  printf '%s\n' "$body" >&2
  echo >&2
  ui_confirm "As informações estão corretas?"
}