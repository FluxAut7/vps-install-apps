#!/usr/bin/env bash

recipe_n8n_install() {
  ui_clear
  ui_title "Instalar n8n"
  dependencies_confirm "n8n" || return 0
  dependencies_require_base

  recipe_postgres_ensure_default

  local suffix stack_name editor_domain webhook_domain encryption_key redis_password stack_file network_name
  suffix="$(ui_input "Sufixo opcional da stack, vazio para n8n" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="n8n_$suffix"
  else
    stack_name="n8n"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  editor_domain="$(ui_input "Domínio do editor n8n, ex: n8n.seudomínio.com.br" "")"
  webhook_domain="$(ui_input "Domínio dos webhooks n8n, ex: webhook.seudomínio.com.br" "$editor_domain")"
  [[ -n "$editor_domain" && -n "$webhook_domain" ]] || fail "Domínios obrigatórios."

  local pg_file pg_host pg_pass
  pg_file="$(recipe_postgres_default_file)"
  pg_host="$(state_get POSTGRES_HOST "$pg_file")"
  pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"

  local database
  database="${stack_name}_queue"
  recipe_postgres_create_database "$database"

  encryption_key="$(state_random_hex 16)"
  redis_password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/n8n.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    NETWORK_NAME "$network_name" \
    EDITOR_DOMAIN "$editor_domain" \
    WEBHOOK_DOMAIN "$webhook_domain" \
    POSTGRES_HOST "$pg_host" \
    POSTGRES_PASSWORD "$pg_pass" \
    POSTGRES_DATABASE "$database" \
    N8N_ENCRYPTION_KEY "$encryption_key" \
    REDIS_PASSWORD "$redis_password"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "n8n" "$editor_domain" "n8nio/n8n:latest" "$stack_file"
  state_set WEBHOOK_DOMAIN "$webhook_domain" "$APP_STATE_DIR/${stack_name}.env"
  state_set N8N_ENCRYPTION_KEY "$encryption_key" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_DATABASE "$database" "$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_PASSWORD "$redis_password" "$APP_STATE_DIR/${stack_name}.env"

  ui_success "n8n instalado."
  echo "Editor: https://$editor_domain"
  echo "Webhook: https://$webhook_domain"
  ui_pause
}
