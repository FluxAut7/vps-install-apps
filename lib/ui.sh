#!/usr/bin/env bash

ui_clear() {
  clear 2>/dev/null || true
}

ui_term_width() {
  local width
  width="$(tput cols 2>/dev/null || printf '80')"
  if [[ -z "$width" || "$width" -lt 64 ]]; then
    width=64
  fi
  printf '%s' "$width"
}

ui_term_height() {
  local height
  height="$(tput lines 2>/dev/null || printf '24')"
  if [[ -z "$height" || "$height" -lt 20 ]]; then
    height=20
  fi
  printf '%s' "$height"
}

ui_repeat() {
  local char="$1"
  local count="$2"
  local out=""
  local i
  for ((i=0; i<count; i++)); do
    out+="$char"
  done
  printf '%s' "$out"
}

ui_rule() {
  local width
  width="$(ui_term_width)"
  ui_repeat "─" "$width"
}

ui_split_menu_label() {
  local raw="$1"
  local label desc
  if [[ "$raw" == *"||"* ]]; then
    label="${raw%%||*}"
    desc="${raw#*||}"
  else
    label="$raw"
    desc=""
  fi
  printf '%s\n%s' "$label" "$desc"
}

ui_title() {
  local title="$1"
  local subtitle="${2:-}"

  printf '\033[38;5;214m%s\033[0m\n' "$(ui_rule)" >&2
  printf '\033[1;97m%s\033[0m\n' "$title" >&2
  if [[ -n "$subtitle" ]]; then
    printf '\033[38;5;250m%s\033[0m\n' "$subtitle" >&2
  fi
  printf '\033[38;5;214m%s\033[0m\n' "$(ui_rule)" >&2
}

ui_section() {
  local title="$1"
  printf '\n\033[1;96m%s\033[0m\n' "$title" >&2
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

ui_kv() {
  local key="$1"
  local value="$2"
  printf '  \033[38;5;214m%-18s\033[0m %s\n' "$key" "$value" >&2
}

ui_list_item() {
  local key="$1"
  local raw="$2"
  local split label desc
  split="$(ui_split_menu_label "$raw")"
  label="${split%%$'\n'*}"
  desc="${split#*$'\n'}"

  printf '  \033[1;93m[%s]\033[0m %s\n' "$key" "$label" >&2
  if [[ -n "$desc" ]]; then
    printf '      \033[38;5;244m%s\033[0m\n' "$desc" >&2
  fi
}

ui_hint() {
  printf '\033[38;5;244m%s\033[0m\n' "$*" >&2
}

fail() {
  ui_error "$*"
  exit 1
}

ui_pause() {
  echo >&2
  printf '\033[38;5;244mPressione Enter para continuar...\033[0m' >&2
  read -r _
}

ui_has_dialog() {
  command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 2 ]]
}

ui_dialog_size() {
  local width height
  width="$(ui_term_width)"
  height="$(ui_term_height)"

  if (( width > 140 )); then
    width=140
  elif (( width > 8 )); then
    width=$((width - 4))
  fi

  if (( height > 30 )); then
    height=30
  elif (( height > 8 )); then
    height=$((height - 4))
  fi

  if (( width < 96 )); then
    width=96
  fi
  if (( height < 22 )); then
    height=22
  fi

  printf '%s\t%s' "$height" "$width"
}

ui_menu() {
  local title="$1"
  shift

  if ui_has_dialog; then
    local dialog_args=()
    local args=("$@")
    local i split label desc
    for ((i=0; i<${#args[@]}; i+=2)); do
      split="$(ui_split_menu_label "${args[$((i+1))]}")"
      label="${split%%$'\n'*}"
      desc="${split#*$'\n'}"
      dialog_args+=("${args[$i]}" "$label" "$desc")
    done

    local size height width result
    size="$(ui_dialog_size)"
    height="${size%%$'\t'*}"
    width="${size#*$'\t'}"

    result="$(dialog --clear --stdout --item-help --title "$title" --menu "Escolha uma opção:" "$height" "$width" 14 "${dialog_args[@]}")" || true
    printf '%s' "$result"
    return 0
  fi

  ui_section "$title"
  local args=("$@")
  local i
  for ((i=0; i<${#args[@]}; i+=2)); do
    ui_list_item "${args[$i]}" "${args[$((i+1))]}"
  done
  echo >&2
  ui_hint "Digite a opção e pressione Enter."

  local choice
  printf '\033[1;97mOpção:\033[0m ' >&2
  read -r choice
  printf '%s' "$choice"
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"

  if ui_has_dialog; then
    dialog --clear --stdout --inputbox "$prompt" 10 90 "$default" || true
    return 0
  fi

  local value
  if [[ -n "$default" ]]; then
    printf '\033[1;97m%s\033[0m \033[38;5;244m[%s]\033[0m: ' "$prompt" "$default" >&2
    read -r value
    printf '%s' "${value:-$default}"
  else
    printf '\033[1;97m%s\033[0m: ' "$prompt" >&2
    read -r value
    printf '%s' "$value"
  fi
}

ui_password() {
  local prompt="$1"

  if ui_has_dialog; then
    dialog --clear --stdout --passwordbox "$prompt" 10 90 || true
    return 0
  fi

  local value
  printf '\033[1;97m%s\033[0m: ' "$prompt" >&2
  read -r -s value
  echo >&2
  printf '%s' "$value"
}

ui_confirm() {
  local prompt="$1"

  if ui_has_dialog; then
    dialog --clear --yesno "$prompt" 10 90
    return $?
  fi

  local answer
  printf '\033[1;97m%s\033[0m \033[38;5;244m(S/N)\033[0m: ' "$prompt" >&2
  read -r answer
  [[ "$answer" =~ ^[SsYy]$ ]]
}

ui_confirm_values() {
  local title="$1"
  local body="$2"

  if ui_has_dialog; then
    dialog --clear --yesno "$body" 18 90
    return $?
  fi

  ui_section "$title"
  printf '%s\n' "$body" >&2
  echo >&2
  ui_confirm "As informações estão corretas?"
}