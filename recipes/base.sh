#!/usr/bin/env bash

recipe_base_install() {
  ui_clear
  ui_title "Preparar VPS"
  system_detect_os

  local portainer_domain portainer_user portainer_password server_name network_name ssl_email
  portainer_domain="$(ui_input "Dominio do Portainer, ex: portainer.seudominio.com.br" "$(state_get PORTAINER_DOMAIN "$STATE_DIR/config.env" || true)")"
  portainer_user="$(ui_input "Usuario admin do Portainer" "admin")"
  portainer_password="$(ui_password "Senha admin do Portainer, minimo recomendado 12 caracteres")"
  server_name="$(ui_input "Nome do servidor, sem espacos" "$(hostname)")"
  network_name="$(ui_input "Nome da rede interna do Swarm" "vps_public")"
  ssl_email="$(ui_input "Email para certificados Let's Encrypt" "")"

  [[ -n "$portainer_domain" && -n "$portainer_user" && -n "$portainer_password" && -n "$network_name" && -n "$ssl_email" ]] \
    || fail "Campos obrigatorios nao preenchidos."

  local summary
  summary="Portainer: https://$portainer_domain
Usuario: $portainer_user
Servidor: $server_name
Rede interna: $network_name
Email SSL: $ssl_email"
  ui_confirm_values "Confirmar dados" "$summary" || return 0

  system_install_docker
  system_init_swarm
  system_ensure_network "$network_name"

  state_set SERVER_NAME "$server_name"
  state_set NETWORK_NAME "$network_name"
  state_set SSL_EMAIL "$ssl_email"
  state_set PORTAINER_DOMAIN "$portainer_domain"

  local traefik_stack portainer_stack
  traefik_stack="$(stack_path traefik)"
  portainer_stack="$(stack_path portainer)"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/traefik.yml" "$traefik_stack" \
    NETWORK_NAME "$network_name" \
    SSL_EMAIL "$ssl_email"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/portainer.yml" "$portainer_stack" \
    NETWORK_NAME "$network_name" \
    PORTAINER_DOMAIN "$portainer_domain"

  ui_info "Instalando Traefik via docker stack deploy..."
  docker stack deploy --prune --resolve-image always -c "$traefik_stack" traefik
  system_wait_stack traefik 180 || true

  ui_info "Instalando Portainer via docker stack deploy..."
  docker stack deploy --prune --resolve-image always -c "$portainer_stack" portainer
  system_wait_stack portainer 240 || true

  recipe_base_init_portainer "$portainer_domain" "$portainer_user" "$portainer_password"

  state_register_app "traefik" "traefik" "base" "" "traefik:v3.4.0" "$traefik_stack"
  state_register_app "portainer" "portainer" "base" "$portainer_domain" "portainer/portainer-ce:latest" "$portainer_stack"

  ui_success "Base instalada."
  ui_warn "Confirme se o DNS do dominio aponta para esta VPS antes de depender do HTTPS."
  ui_pause
}

recipe_base_init_portainer() {
  local domain="$1"
  local user="$2"
  local password="$3"
  local api_url="http://127.0.0.1:9000"

  ui_info "Inicializando usuario admin do Portainer..."
  local attempt response
  for attempt in 1 2 3 4 5 6; do
    response="$(curl -sS -X POST "$api_url/api/users/admin/init" \
      -H "Content-Type: application/json" \
      -d "{\"Username\":\"$user\",\"Password\":\"$password\"}" || true)"
    if printf '%s' "$response" | grep -q '"Username"'; then
      ui_success "Usuario admin criado no Portainer."
      break
    fi
    if printf '%s' "$response" | grep -qi 'already'; then
      ui_warn "Portainer ja inicializado. Salvando credenciais informadas."
      break
    fi
    sleep 5
  done

  state_set PORTAINER_URL "https://$domain" "$STATE_DIR/portainer.env"
  state_set PORTAINER_API_URL "$api_url" "$STATE_DIR/portainer.env"
  state_set PORTAINER_USER "$user" "$STATE_DIR/portainer.env"
  state_set PORTAINER_PASSWORD "$password" "$STATE_DIR/portainer.env"

  portainer_login >/dev/null || {
    ui_warn "Nao foi possivel autenticar via $api_url. Tentando HTTPS do dominio..."
    state_set PORTAINER_API_URL "https://$domain" "$STATE_DIR/portainer.env"
    portainer_login >/dev/null
  }

  ui_success "Portainer API configurada."
}
