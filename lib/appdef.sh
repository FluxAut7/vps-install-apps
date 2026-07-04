#!/usr/bin/env bash

appdef_reset() {
  unset APP_SLUG APP_LABEL APP_DESCRIPTION APP_CATEGORY APP_IMAGE_REPO APP_TESTED_TAGS \
    APP_DOMAINS APP_SECRETS APP_INPUTS APP_NEEDS_POSTGRES APP_NEEDS_REDIS APP_SUMMARY_LINES \
    APP_STATE_LINES
}

appdef_dir() {
  printf '%s/apps/%s' "$VPS_INSTALLER_SOURCE_DIR" "$1"
}

appdef_template_path() {
  printf '%s/stack.yml' "$(appdef_dir "$1")"
}

appdef_list_slugs() {
  local dir
  for dir in "$VPS_INSTALLER_SOURCE_DIR"/apps/*/; do
    [[ -f "${dir}app.env" ]] || continue
    basename "${dir%/}"
  done
}

appdef_label_or_default() {
  local app_type="$1"
  local default="$2"
  local file="$VPS_INSTALLER_SOURCE_DIR/apps/$app_type/app.env"
  [[ -f "$file" ]] || { printf '%s' "$default"; return 0; }

  local label
  label="$(awk -F= '/^APP_LABEL=/ { sub(/^APP_LABEL=/, ""); print; exit }' "$file")"
  label="${label%\"}"
  label="${label#\"}"
  [[ -n "$label" ]] && printf '%s' "$label" || printf '%s' "$default"
}

appdef_load() {
  local slug="$1"
  local dir file template
  dir="$(appdef_dir "$slug")"
  file="$dir/app.env"
  template="$dir/stack.yml"

  appdef_reset
  [[ -f "$file" ]] || fail "Manifesto não encontrado para app: $slug"
  [[ -f "$template" ]] || fail "Template não encontrado para app: $slug"

  # shellcheck disable=SC1090
  . "$file"

  [[ "${APP_SLUG:-}" == "$slug" ]] || fail "Manifesto inconsistente: APP_SLUG não corresponde a '$slug' em $file."
  [[ -n "${APP_LABEL:-}" ]] || fail "Manifesto inválido ($slug): APP_LABEL ausente."
  [[ -n "${APP_IMAGE_REPO:-}" ]] || fail "Manifesto inválido ($slug): APP_IMAGE_REPO ausente."
  [[ -n "${APP_TESTED_TAGS:-}" ]] || fail "Manifesto inválido ($slug): APP_TESTED_TAGS ausente."

  APP_CATEGORY="${APP_CATEGORY:-outros}"
  APP_DESCRIPTION="${APP_DESCRIPTION:-}"
  APP_NEEDS_POSTGRES="${APP_NEEDS_POSTGRES:-false}"
  APP_NEEDS_REDIS="${APP_NEEDS_REDIS:-false}"
  APP_DOMAINS="${APP_DOMAINS:-}"
  APP_SECRETS="${APP_SECRETS:-}"
  APP_INPUTS="${APP_INPUTS:-}"
  APP_SUMMARY_LINES="${APP_SUMMARY_LINES:-}"
  APP_STATE_LINES="${APP_STATE_LINES:-}"
}

appdef_dependencies_text() {
  local text="Dependências:
- Base da VPS instalada: Docker, Swarm, rede interna, Traefik e Portainer
- Portainer API configurada"
  [[ "${APP_NEEDS_POSTGRES:-false}" == "true" ]] && text="$text
- PostgreSQL padrão: instalado automaticamente se ainda não existir"
  [[ "${APP_NEEDS_REDIS:-false}" == "true" ]] && text="$text
- Redis: senha gerada e serviço próprio incluído na stack"
  printf '%s' "$text"
}

appdef_env_override_var() {
  local slug="$1"
  printf 'VPSI_TESTED_%s_VERSIONS' "$(printf '%s' "$slug" | tr '[:lower:]-' '[:upper:]_')"
}

appdef_select_tag() {
  local slug="$1"
  local current_override="${2:-}"
  local override_var override_csv csv current
  override_var="$(appdef_env_override_var "$slug")"
  override_csv="${!override_var:-}"
  csv="${override_csv:-$APP_TESTED_TAGS}"
  current="${current_override:-${csv%%,*}}"

  local -a values=()
  IFS=',' read -r -a values <<< "$csv"
  catalog_pick_one "Versão de $APP_LABEL" "Tag testada de $APP_LABEL" "$current" "${values[@]}"
}

appdef_image() {
  printf '%s:%s' "$APP_IMAGE_REPO" "$1"
}

appdef_split_semicolons() {
  local input="$1"
  local bak="$IFS"
  IFS=';' read -r -a __appdef_split_result <<< "$input"
  IFS="$bak"
}

appdef_apply_state_lines() {
  # Persiste variáveis derivadas (ex.: POSTGRES_HOST/URL de uma dependência) no
  # arquivo de estado do app. Cada item é "CHAVE=modelo", com placeholders
  # __VAR__ resolvidos a partir do estado já salvo do app.
  local app_file="$1"
  [[ -n "$APP_STATE_LINES" ]] || return 0

  # shellcheck disable=SC1090
  (
    . "$app_file"
    local -a lines=()
    appdef_split_semicolons "$APP_STATE_LINES"
    lines=("${__appdef_split_result[@]}")

    local line key template
    for line in "${lines[@]}"; do
      [[ -n "$line" ]] || continue
      key="${line%%=*}"
      template="${line#*=}"
      while [[ "$template" == *"__"*"__"* ]]; do
        local before rest var value
        before="${template%%__*}"
        rest="${template#*__}"
        var="${rest%%__*}"
        rest="${rest#*__}"
        value="$(eval 'printf "%s" "${'"$var"':-}"')"
        template="${before}${value}${rest}"
      done
      state_set "$key" "$template" "$app_file"
    done
  )
}

appdef_render_summary() {
  local app_file="$1"
  [[ -n "$APP_SUMMARY_LINES" ]] || return 0

  # shellcheck disable=SC1090
  (
    . "$app_file"
    local -a lines=()
    appdef_split_semicolons "$APP_SUMMARY_LINES"
    lines=("${__appdef_split_result[@]}")

    local line
    for line in "${lines[@]}"; do
      [[ -n "$line" ]] || continue
      while [[ "$line" == *"__"*"__"* ]]; do
        local before rest var value
        before="${line%%__*}"
        rest="${line#*__}"
        var="${rest%%__*}"
        rest="${rest#*__}"
        value="$(eval 'printf "%s" "${'"$var"':-}"')"
        line="${before}${value}${rest}"
      done
      printf '%s\n' "$line"
    done
  )
}
