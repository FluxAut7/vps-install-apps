#!/usr/bin/env bash

recipe_n8n_install() {
  ui_clear
  ui_title "Instalar n8n"
  dependencies_confirm "n8n" || return 0
  dependencies_require_base

  recipe_postgres_ensure_default

  local suffix stack_name editor_domain webhook_domain n8n_version n8n_image n8n_runners_image encryption_key runners_auth_token redis_password stack_file network_name
  suffix="$(ui_input "Sufixo opcional da stack, vazio para n8n" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="n8n_$suffix"
  else
    stack_name="n8n"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  n8n_version="$(catalog_select_n8n_version)"
  n8n_image="$(catalog_n8n_image "$n8n_version")"
  n8n_runners_image="$(catalog_n8n_runners_image "$n8n_version")"
  editor_domain="$(ui_input "Domínio do editor n8n, ex: n8n.seudomínio.com.br" "")"
  webhook_domain="$(ui_input "Domínio dos webhooks n8n, ex: webhook.seudomínio.com.br" "$editor_domain")"
  [[ -n "$editor_domain" && -n "$webhook_domain" ]] || fail "Domínios obrigatórios."
  dns_confirm_domain "$editor_domain" || return 0
  [[ "$webhook_domain" == "$editor_domain" ]] || dns_confirm_domain "$webhook_domain" || return 0

  local pg_file pg_host pg_pass
  pg_file="$(recipe_postgres_default_file)"
  pg_host="$(state_get POSTGRES_HOST "$pg_file")"
  pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"

  local database
  database="${stack_name}_queue"
  recipe_postgres_create_database "$database"

  encryption_key="$(state_random_hex 16)"
  runners_auth_token="$(state_random_hex 32)"
  redis_password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/n8n.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    NETWORK_NAME "$network_name" \
    EDITOR_DOMAIN "$editor_domain" \
    WEBHOOK_DOMAIN "$webhook_domain" \
    N8N_IMAGE "$n8n_image" \
    N8N_RUNNERS_IMAGE "$n8n_runners_image" \
    N8N_RUNNERS_AUTH_TOKEN "$runners_auth_token" \
    POSTGRES_HOST "$pg_host" \
    POSTGRES_PASSWORD "$pg_pass" \
    POSTGRES_DATABASE "$database" \
    N8N_ENCRYPTION_KEY "$encryption_key" \
    REDIS_PASSWORD "$redis_password"

  local deploy_ok=1
  portainer_deploy_stack "$stack_name" "$stack_file" || deploy_ok=0
  state_register_app "$stack_name" "$stack_name" "n8n" "$editor_domain" "$n8n_image" "$stack_file"
  state_set WEBHOOK_DOMAIN "$webhook_domain" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_VERSION "$n8n_version" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_IMAGE "$n8n_image" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_RUNNERS_IMAGE "$n8n_runners_image" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_ENCRYPTION_KEY "$encryption_key" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_RUNNERS_AUTH_TOKEN "$runners_auth_token" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_DATABASE "$database" "$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_PASSWORD "$redis_password" "$APP_STATE_DIR/${stack_name}.env"

  if [[ "$deploy_ok" -eq 0 ]]; then
    ui_warn "'$stack_name' foi registrada no inventário, mas os serviços não convergiram. Revise antes de usar."
    ui_pause
    return 0
  fi

  system_wait_https "$editor_domain" 120 || true

  ui_success "n8n instalado."
  echo "Editor: https://$editor_domain"
  echo "Webhook: https://$webhook_domain"
  echo "Runners: habilitado ($n8n_runners_image)"
  ui_pause
}