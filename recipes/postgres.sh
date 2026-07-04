#!/usr/bin/env bash
# PostgreSQL é instalado como qualquer outra ferramenta pelo catálogo
# (apps/postgres via recipe_generic_install). Este arquivo mantém apenas os
# auxiliares do "PostgreSQL padrão" compartilhado, usados por apps que dependem
# do banco (APP_NEEDS_POSTGRES=true).

# Instala a stack "postgres" padrão de forma não interativa, gravando o contrato
# (POSTGRES_HOST/USER/PASSWORD/URL) que os apps dependentes consomem.
recipe_postgres_install_default() {
  dependencies_require_base

  local stack_name="postgres"
  if portainer_stack_exists "$stack_name"; then
    return 0
  fi

  appdef_load "postgres"

  local app_tag app_image password stack_file network_name app_file
  app_tag="$(appdef_select_tag "postgres")"
  [[ -n "$app_tag" ]] || fail "Nenhuma tag testada de PostgreSQL disponível."
  app_image="$(appdef_image "$app_tag")"
  password="$(state_random_hex 16)"
  stack_file="$(stack_path "$stack_name")"
  network_name="$(state_get NETWORK_NAME)"
  [[ -n "$network_name" ]] || fail "Rede não configurada. Instale a base primeiro."
  app_file="$APP_STATE_DIR/${stack_name}.env"

  stack_render "$(appdef_template_path postgres)" "$stack_file" \
    STACK_NAME "$stack_name" \
    NETWORK_NAME "$network_name" \
    APP_IMAGE "$app_image" \
    APP_IMAGE_TAG "$app_tag" \
    POSTGRES_PASSWORD "$password"

  local deploy_ok=1
  portainer_deploy_stack "$stack_name" "$stack_file" || deploy_ok=0
  state_register_app "$stack_name" "$stack_name" "postgres" "" "$app_image" "$stack_file"
  state_set POSTGRES_PASSWORD "$password" "$app_file"
  appdef_apply_state_lines "$app_file"

  [[ "$deploy_ok" -eq 1 ]] || fail "PostgreSQL padrão não convergiu. Verifique 'docker service ls' antes de continuar."
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
  ui_warn "PostgreSQL padrão não encontrado. Instalando stack postgres automaticamente."
  recipe_postgres_install_default
}

recipe_postgres_create_database() {
  local database="$1"
  local pg_file
  pg_file="$(recipe_postgres_default_file)" || fail "PostgreSQL padrão não encontrado."
  state_source "$pg_file"

  local container_id
  container_id="$(docker ps --filter "name=postgres_postgres" --format '{{.ID}}' | head -n 1)"
  [[ -n "$container_id" ]] || {
    ui_warn "Container Postgres ainda não encontrado. O banco será criado pela aplicação se suportado."
    return 0
  }

  docker exec -i "$container_id" psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = '$database'" \
    | grep -q 1 || docker exec -i "$container_id" createdb -U postgres "$database" || true
}
