#!/usr/bin/env bash

recipe_uptime_kuma_install() {
  ui_clear
  ui_title "Instalar Uptime Kuma"
  system_require_docker
  portainer_require_config

  local suffix stack_name domain stack_file network_name image
  suffix="$(ui_input "Sufixo opcional da stack, vazio para uptimekuma" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="uptimekuma_$suffix"
  else
    stack_name="uptimekuma"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  domain="$(ui_input "Dominio do Uptime Kuma, ex: uptime.seudominio.com.br" "")"
  [[ -n "$domain" ]] || fail "Dominio obrigatorio."

  image="louislam/uptime-kuma:1"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede nao configurada. Instale a base primeiro."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/uptime-kuma.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    NETWORK_NAME "$network_name" \
    DOMAIN "$domain" \
    IMAGE "$image"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "uptime-kuma" "$domain" "$image" "$stack_file"
  state_set UPTIME_KUMA_DOMAIN "$domain" "$APP_STATE_DIR/${stack_name}.env"
  state_set UPTIME_KUMA_IMAGE "$image" "$APP_STATE_DIR/${stack_name}.env"

  ui_success "Uptime Kuma instalado."
  echo "URL: https://$domain"
  echo "Imagem: $image"
  ui_pause
}