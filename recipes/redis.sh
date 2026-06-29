#!/usr/bin/env bash

recipe_redis_install() {
  ui_clear
  ui_title "Instalar Redis"
  system_require_docker
  portainer_require_config

  local suffix stack_name service_name password stack_file network_name
  suffix="$(ui_input "Sufixo opcional da stack, vazio para redis" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="redis_$suffix"
    service_name="redis_$suffix"
  else
    stack_name="redis"
    service_name="redis"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede nao configurada. Instale a base primeiro."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/redis.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    SERVICE_NAME "$service_name" \
    NETWORK_NAME "$network_name" \
    REDIS_PASSWORD "$password"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "redis" "" "redis:7-alpine" "$stack_file"
  state_set REDIS_HOST "$service_name" "$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_PASSWORD "$password" "$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_URL "redis://:$password@$service_name:6379/0" "$APP_STATE_DIR/${stack_name}.env"

  ui_success "Redis instalado."
  echo "Host: $service_name"
  echo "Senha: $password"
  ui_pause
}
