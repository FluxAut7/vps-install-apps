#!/usr/bin/env bash

recipe_postgres_install() {
  ui_clear
  ui_title "Instalar PostgreSQL"
  dependencies_confirm "postgres" || return 0
  dependencies_require_base

  local suffix stack_name service_name password stack_file
  suffix="$(ui_input "Sufixo opcional da stack, vazio para postgres" "")"
  if [[ -n "$suffix" ]]; then
    stack_name="postgres_$suffix"
    service_name="postgres_$suffix"
  else
    stack_name="postgres"
    service_name="postgres"
  fi

  if portainer_stack_exists "$stack_name"; then
    fail "Stack ja existe: $stack_name"
  fi

  password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"

  local network_name
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede nao configurada. Instale a base primeiro."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/postgres.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    SERVICE_NAME "$service_name" \
    NETWORK_NAME "$network_name" \
    POSTGRES_PASSWORD "$password"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "postgres" "" "postgres:16-alpine" "$stack_file"
  state_set POSTGRES_HOST "$service_name" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_USER "postgres" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_PASSWORD "$password" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_URL "postgresql://postgres:$password@$service_name:5432/postgres" "$APP_STATE_DIR/${stack_name}.env"

  ui_success "PostgreSQL instalado."
  echo "Host: $service_name"
  echo "Usuario: postgres"
  echo "Senha: $password"
  ui_pause
}

recipe_postgres_install_default() {
  dependencies_require_base

  local stack_name="postgres"
  local service_name="postgres"
  local password stack_file network_name

  if portainer_stack_exists "$stack_name"; then
    return 0
  fi

  password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede nao configurada. Instale a base primeiro."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/postgres.yml" "$stack_file" \
    STACK_NAME "$stack_name" \
    SERVICE_NAME "$service_name" \
    NETWORK_NAME "$network_name" \
    POSTGRES_PASSWORD "$password"

  portainer_deploy_stack "$stack_name" "$stack_file"
  state_register_app "$stack_name" "$stack_name" "postgres" "" "postgres:16-alpine" "$stack_file"
  state_set POSTGRES_HOST "$service_name" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_USER "postgres" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_PASSWORD "$password" "$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_URL "postgresql://postgres:$password@$service_name:5432/postgres" "$APP_STATE_DIR/${stack_name}.env"
}
recipe_postgres_default_file() {
  if [[ -f "$APP_STATE_DIR/postgres.env" ]]; then
    printf '%s' "$APP_STATE_DIR/postgres.env"
    return 0
  fi
  return 1
}

recipe_postgres_ensure_default() {
  if recipe_postgres_default_file >/dev/null; then
    return 0
  fi
  ui_warn "PostgreSQL padrao nao encontrado. Instalando stack postgres automaticamente."
  recipe_postgres_install_default
}

recipe_postgres_create_database() {
  local database="$1"
  local pg_file
  pg_file="$(recipe_postgres_default_file)" || fail "PostgreSQL padrao nao encontrado."
  state_source "$pg_file"

  local container_id
  container_id="$(docker ps --filter "name=postgres_postgres" --format '{{.ID}}' | head -n 1)"
  [[ -n "$container_id" ]] || {
    ui_warn "Container Postgres ainda nao encontrado. O banco sera criado pela aplicacao se suportado."
    return 0
  }

  docker exec -i "$container_id" psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$database'" \
    | grep -q 1 || docker exec -i "$container_id" createdb -U postgres "$database" || true
}
