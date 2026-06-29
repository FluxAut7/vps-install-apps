#!/usr/bin/env bash

recipe_evolution_install() {
  ui_clear
  ui_title "Instalar Evolution API"
  system_require_docker
  portainer_require_config

  recipe_postgres_ensure_default

  local suffix stack_name domain api_key redis_password stack_file network_name
  suffix="$(ui_input "Sufixo opcional da stack, vazio para evolution" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="evolution_$suffix"
  else
    stack_name="evolution"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  domain="$(ui_input "Dominio da Evolution API, ex: evolution.seudominio.com.br" "")"
  [[ -n "$domain" ]] || fail "Dominio obrigatorio."

  local pg_file pg_host pg_pass database
  pg_file="$(recipe_postgres_default_file)"
  pg_host="$(state_get POSTGRES_HOST "$pg_file")"
  pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"
  database="$stack_name"
  recipe_postgres_create_database "$database"

  api_key="$(state_random_hex 16)"
  redis_password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/evolution-api.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    NETWORK_NAME "$network_name" \
    DOMAIN "$domain" \
    API_KEY "$api_key" \
    POSTGRES_HOST "$pg_host" \
    POSTGRES_PASSWORD "$pg_pass" \
    POSTGRES_DATABASE "$database" \
    REDIS_PASSWORD "$redis_password"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "evolution-api" "$domain" "evoapicloud/evolution-api:latest" "$stack_file"
  state_set EVOLUTION_API_KEY "$api_key" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_DATABASE "$database" "$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_PASSWORD "$redis_password" "$APP_STATE_DIR/${stack_name}.env"

  ui_success "Evolution API instalada."
  echo "URL: https://$domain"
  echo "API key: $api_key"
  ui_pause
}
