#!/usr/bin/env bash

stack_sed_escape() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

stack_render() {
  local template="$1"
  local output="$2"
  shift 2

  [[ -f "$template" ]] || fail "Template não encontrado: $template"
  mkdir -p "$(dirname "$output")"
  cp "$template" "$output"

  while (( "$#" )); do
    local key="$1"
    local value="$2"
    shift 2
    sed -i "s|__${key}__|$(stack_sed_escape "$value")|g" "$output"
  done
}

stack_validate_file() {
  local file="$1"
  [[ -s "$file" ]] || fail "Stack vazia ou inexistente: $file"
  grep -q '^services:' "$file" || fail "Stack invalida, secao services ausente: $file"
}

stack_path() {
  local name="$1"
  printf '%s/%s.yml' "$STACKS_DIR" "$name"
}
