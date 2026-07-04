#!/usr/bin/env bash
# shellcheck disable=SC2154  # __appdef_split_result é preenchido por appdef_split_semicolons (lib/appdef.sh)

recipe_generic_install() {
  local slug="$1"
  appdef_load "$slug"

  ui_clear
  ui_title "Instalar $APP_LABEL"
  ui_confirm_values "Mapa de dependências" "$(appdef_dependencies_text)" || return 0
  dependencies_require_base

  [[ "$APP_NEEDS_POSTGRES" == "true" ]] && recipe_postgres_ensure_default

  local suffix stack_name
  suffix="$(ui_input "Sufixo opcional da stack, vazio para $slug" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="${slug}_${suffix}"
  else
    stack_name="$slug"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  local app_tag app_image
  app_tag="$(appdef_select_tag "$slug")"
  [[ -n "$app_tag" ]] || return 0
  app_image="$(appdef_image "$app_tag")"

  local network_name
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede não configurada. Instale a base primeiro."

  local app_file="$APP_STATE_DIR/${stack_name}.env"
  local first_domain=""
  local -a render_args=(STACK_NAME "$stack_name" NETWORK_NAME "$network_name" APP_IMAGE "$app_image")

  local item var prompt value

  if [[ -n "$APP_DOMAINS" ]]; then
    appdef_split_semicolons "$APP_DOMAINS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="${item%%:*}"
      prompt="${item#*:}"
      value="$(ui_input "$prompt" "")"
      [[ -n "$value" ]] || fail "Domínio obrigatório: $prompt"
      dns_confirm_domain "$value" || return 0
      render_args+=("$var" "$value")
      state_set "$var" "$value" "$app_file"
      [[ -z "$first_domain" ]] && first_domain="$value"
    done
  fi

  if [[ -n "$APP_INPUTS" ]]; then
    appdef_split_semicolons "$APP_INPUTS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="$(printf '%s' "$item" | awk -F: '{print $1}')"
      prompt="$(printf '%s' "$item" | awk -F: '{print $2}')"
      local default_value
      default_value="$(printf '%s' "$item" | awk -F: '{print $3}')"
      value="$(ui_input "$prompt" "$default_value")"
      render_args+=("$var" "$value")
      state_set "$var" "$value" "$app_file"
    done
  fi

  if [[ -n "$APP_SECRETS" ]]; then
    appdef_split_semicolons "$APP_SECRETS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="${item%%:*}"
      local generator="${item#*:}"
      case "$generator" in
        hex16) value="$(state_random_hex 16)" ;;
        hex32) value="$(state_random_hex 32)" ;;
        *) fail "Gerador de segredo desconhecido para $var: $generator" ;;
      esac
      render_args+=("$var" "$value")
      state_set "$var" "$value" "$app_file"
    done
  fi

  if [[ "$APP_NEEDS_POSTGRES" == "true" ]]; then
    local pg_file pg_host pg_pass database
    pg_file="$(recipe_postgres_default_file)"
    pg_host="$(state_get POSTGRES_HOST "$pg_file")"
    pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"
    database="${stack_name}_db"
    recipe_postgres_create_database "$database"
    render_args+=(POSTGRES_HOST "$pg_host" POSTGRES_PASSWORD "$pg_pass" POSTGRES_DATABASE "$database")
    state_set POSTGRES_DATABASE "$database" "$app_file"
  fi

  if [[ "$APP_NEEDS_REDIS" == "true" ]]; then
    local redis_password
    redis_password="$(state_random_hex 16)"
    render_args+=(REDIS_PASSWORD "$redis_password")
    state_set REDIS_PASSWORD "$redis_password" "$app_file"
  fi

  local stack_file
  stack_file="$(stack_path "$stack_name")"
  stack_render "$(appdef_template_path "$slug")" "$stack_file" "${render_args[@]}"

  local deploy_ok=1
  portainer_deploy_stack "$stack_name" "$stack_file" || deploy_ok=0
  state_register_app "$stack_name" "$stack_name" "$slug" "$first_domain" "$app_image" "$stack_file"

  if [[ "$deploy_ok" -eq 0 ]]; then
    ui_warn "'$stack_name' foi registrada no inventário, mas os serviços não convergiram. Revise antes de usar."
    ui_pause
    return 0
  fi

  [[ -n "$first_domain" ]] && { system_wait_https "$first_domain" 120 || true; }

  ui_success "$APP_LABEL instalado."
  if [[ -n "$APP_SUMMARY_LINES" ]]; then
    appdef_render_summary "$app_file"
  fi
  ui_pause
}

recipe_generic_catalog_menu() {
  local -a slugs=()
  local slug
  while read -r slug; do
    [[ -n "$slug" ]] || continue
    slugs+=("$slug")
  done < <(appdef_list_slugs | sort)

  if [[ "${#slugs[@]}" -eq 0 ]]; then
    installer_header
    ui_warn "Nenhum app do catálogo data-driven disponível em apps/."
    ui_pause
    return 0
  fi

  local -a items=()
  for slug in "${slugs[@]}"; do
    appdef_load "$slug"
    items+=("$slug" "$APP_LABEL||$APP_DESCRIPTION")
  done

  local selected
  selected="$(installer_menu_with_summary "Catálogo de ferramentas" "${items[@]}" "0" "Voltar||Retorna ao menu Ferramentas.")"
  [[ -n "$selected" && "$selected" != "0" ]] || return 0

  recipe_generic_install "$selected"
}
