#!/usr/bin/env bash
# shellcheck disable=SC2154  # __appdef_split_result é preenchido por appdef_split_semicolons (lib/appdef.sh)

recipe_update_apply_stack() {
  local stack_name="$1"
  local stack_file="$2"
  stack_validate_file "$stack_file"
  ui_info "Aplicando atualização da stack '$stack_name'..."
  docker stack deploy --prune --resolve-image always -c "$stack_file" "$stack_name"
  system_wait_stack "$stack_name" 180 || true
  ui_success "Stack atualizada: $stack_name"
}

recipe_update_traefik() {
  local app_file="$APP_STATE_DIR/traefik.env"
  local network_name ssl_email stack_file traefik_image
  network_name="$(state_get NETWORK_NAME)"
  ssl_email="$(state_get SSL_EMAIL)"
  [[ -n "$network_name" && -n "$ssl_email" ]] || fail "Base da VPS incompleta para atualizar o Traefik."

  stack_file="$(stack_path traefik)"
  traefik_image="$(catalog_traefik_image)"
  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/traefik.yml" "$stack_file" \
    NETWORK_NAME "$network_name" \
    SSL_EMAIL "$ssl_email" \
    TRAEFIK_IMAGE "$traefik_image"

  recipe_update_apply_stack "traefik" "$stack_file"
  state_set APP_IMAGE "$traefik_image" "$app_file"
  state_set TRAEFIK_IMAGE "$traefik_image" "$app_file"
}

recipe_update_portainer() {
  local app_file="$APP_STATE_DIR/portainer.env"
  state_source "$app_file"

  local channel image agent_image network_name stack_file domain
  channel="$(catalog_select_portainer_channel "${PORTAINER_CHANNEL:-$(state_get PORTAINER_CHANNEL || true)}")"
  image="$(catalog_portainer_image "$channel")"
  agent_image="$(catalog_portainer_agent_image "$channel")"
  network_name="$(state_get NETWORK_NAME)"
  domain="${APP_DOMAIN:-$(state_get PORTAINER_DOMAIN || true)}"
  [[ -n "$network_name" && -n "$domain" ]] || fail "Base da VPS incompleta para atualizar o Portainer."

  stack_file="$(stack_path portainer)"
  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/portainer.yml" "$stack_file" \
    NETWORK_NAME "$network_name" \
    PORTAINER_DOMAIN "$domain" \
    PORTAINER_IMAGE "$image" \
    PORTAINER_AGENT_IMAGE "$agent_image"

  recipe_update_apply_stack "portainer" "$stack_file"
  state_set PORTAINER_CHANNEL "$channel"
  state_set PORTAINER_IMAGE "$image"
  state_set PORTAINER_AGENT_IMAGE "$agent_image"
  state_set APP_IMAGE "$image" "$app_file"
  state_set PORTAINER_CHANNEL "$channel" "$app_file"
  state_set PORTAINER_AGENT_IMAGE "$agent_image" "$app_file"
}

recipe_update_postgres() {
  local app_file="$1"
  state_source "$app_file"

  local postgres_tag postgres_image network_name service_name stack_file
  postgres_tag="$(catalog_select_postgres_tag "${POSTGRES_TAG:-${APP_IMAGE##*:}}")"
  postgres_image="$(catalog_postgres_image "$postgres_tag")"
  network_name="$(state_get NETWORK_NAME)"
  service_name="${POSTGRES_HOST:-$STACK_NAME}"
  stack_file="$(stack_path "$STACK_NAME")"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/postgres.yml" "$stack_file" \
    STACK_NAME "$STACK_NAME" \
    SERVICE_NAME "$service_name" \
    NETWORK_NAME "$network_name" \
    POSTGRES_IMAGE "$postgres_image" \
    POSTGRES_PASSWORD "$POSTGRES_PASSWORD"

  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$postgres_image" "$app_file"
  state_set POSTGRES_TAG "$postgres_tag" "$app_file"
}

recipe_update_redis() {
  local app_file="$1"
  state_source "$app_file"

  local redis_tag redis_image network_name service_name stack_file
  redis_tag="$(catalog_select_redis_tag "${REDIS_TAG:-${APP_IMAGE##*:}}")"
  redis_image="$(catalog_redis_image "$redis_tag")"
  network_name="$(state_get NETWORK_NAME)"
  service_name="${REDIS_HOST:-$STACK_NAME}"
  stack_file="$(stack_path "$STACK_NAME")"

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/redis.yml" "$stack_file" \
    STACK_NAME "$STACK_NAME" \
    SERVICE_NAME "$service_name" \
    NETWORK_NAME "$network_name" \
    REDIS_IMAGE "$redis_image" \
    REDIS_PASSWORD "$REDIS_PASSWORD"

  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$redis_image" "$app_file"
  state_set REDIS_TAG "$redis_tag" "$app_file"
}

recipe_update_n8n() {
  local app_file="$1"
  state_source "$app_file"

  local n8n_version n8n_image n8n_runners_image network_name stack_file pg_file pg_host pg_pass
  n8n_version="$(catalog_select_n8n_version "${N8N_VERSION:-${APP_IMAGE##*:}}")"
  n8n_image="$(catalog_n8n_image "$n8n_version")"
  n8n_runners_image="$(catalog_n8n_runners_image "$n8n_version")"
  network_name="$(state_get NETWORK_NAME)"
  stack_file="$(stack_path "$STACK_NAME")"
  pg_file="$(recipe_postgres_default_file)"
  pg_host="$(state_get POSTGRES_HOST "$pg_file")"
  pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"

  [[ -n "${APP_DOMAIN:-}" && -n "${WEBHOOK_DOMAIN:-}" && -n "${POSTGRES_DATABASE:-}" && -n "${N8N_ENCRYPTION_KEY:-}" && -n "${N8N_RUNNERS_AUTH_TOKEN:-}" && -n "${REDIS_PASSWORD:-}" ]] \
    || fail "Estado local incompleto para atualizar o n8n."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/n8n.yml" "$stack_file" \
    STACK_NAME "$STACK_NAME" \
    NETWORK_NAME "$network_name" \
    EDITOR_DOMAIN "$APP_DOMAIN" \
    WEBHOOK_DOMAIN "$WEBHOOK_DOMAIN" \
    N8N_IMAGE "$n8n_image" \
    N8N_RUNNERS_IMAGE "$n8n_runners_image" \
    N8N_RUNNERS_AUTH_TOKEN "$N8N_RUNNERS_AUTH_TOKEN" \
    POSTGRES_HOST "$pg_host" \
    POSTGRES_PASSWORD "$pg_pass" \
    POSTGRES_DATABASE "$POSTGRES_DATABASE" \
    N8N_ENCRYPTION_KEY "$N8N_ENCRYPTION_KEY" \
    REDIS_PASSWORD "$REDIS_PASSWORD"

  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$n8n_image" "$app_file"
  state_set N8N_VERSION "$n8n_version" "$app_file"
  state_set N8N_IMAGE "$n8n_image" "$app_file"
  state_set N8N_RUNNERS_IMAGE "$n8n_runners_image" "$app_file"
}

recipe_update_uptime_kuma() {
  local app_file="$1"
  state_source "$app_file"

  local major image network_name stack_file
  major="$(catalog_select_uptime_kuma_major "${UPTIME_KUMA_MAJOR_VERSION:-1}")"
  image="$(catalog_uptime_kuma_image "$major")"
  network_name="$(state_get NETWORK_NAME)"
  stack_file="$(stack_path "$STACK_NAME")"

  [[ -n "${APP_DOMAIN:-}" ]] || fail "Estado local incompleto para atualizar o Uptime Kuma."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/uptime-kuma.yml" "$stack_file" \
    STACK_NAME "$STACK_NAME" \
    NETWORK_NAME "$network_name" \
    DOMAIN "$APP_DOMAIN" \
    IMAGE "$image"

  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$image" "$app_file"
  state_set UPTIME_KUMA_IMAGE "$image" "$app_file"
  state_set UPTIME_KUMA_MAJOR_VERSION "$major" "$app_file"
}

recipe_update_evolution_api() {
  local app_file="$1"
  state_source "$app_file"

  local evolution_tag evolution_image network_name stack_file pg_file pg_host pg_pass
  evolution_tag="$(catalog_select_evolution_tag "${EVOLUTION_TAG:-${APP_IMAGE##*:}}")"
  evolution_image="$(catalog_evolution_image "$evolution_tag")"
  network_name="$(state_get NETWORK_NAME)"
  stack_file="$(stack_path "$STACK_NAME")"
  pg_file="$(recipe_postgres_default_file)"
  pg_host="$(state_get POSTGRES_HOST "$pg_file")"
  pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"

  [[ -n "${APP_DOMAIN:-}" && -n "${EVOLUTION_API_KEY:-}" && -n "${POSTGRES_DATABASE:-}" && -n "${REDIS_PASSWORD:-}" ]] \
    || fail "Estado local incompleto para atualizar a Evolution API."

  stack_render "$VPS_INSTALLER_SOURCE_DIR/templates/evolution-api.yml" "$stack_file" \
    STACK_NAME "$STACK_NAME" \
    NETWORK_NAME "$network_name" \
    DOMAIN "$APP_DOMAIN" \
    EVOLUTION_IMAGE "$evolution_image" \
    API_KEY "$EVOLUTION_API_KEY" \
    POSTGRES_HOST "$pg_host" \
    POSTGRES_PASSWORD "$pg_pass" \
    POSTGRES_DATABASE "$POSTGRES_DATABASE" \
    REDIS_PASSWORD "$REDIS_PASSWORD"

  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$evolution_image" "$app_file"
  state_set EVOLUTION_TAG "$evolution_tag" "$app_file"
}

recipe_update_generic() {
  local app_file="$1"
  state_source "$app_file"

  local slug="$APP_TYPE"
  appdef_load "$slug"

  local app_tag app_image
  app_tag="$(appdef_select_tag "$slug" "${APP_IMAGE##*:}")"
  [[ -n "$app_tag" ]] || return 0
  app_image="$(appdef_image "$app_tag")"

  local network_name stack_file
  network_name="$(state_get NETWORK_NAME)"
  stack_file="$(stack_path "$STACK_NAME")"

  local -a render_args=(STACK_NAME "$STACK_NAME" NETWORK_NAME "$network_name" APP_IMAGE "$app_image" APP_IMAGE_TAG "$app_tag")
  local item var value

  if [[ -n "$APP_DOMAINS" ]]; then
    appdef_split_semicolons "$APP_DOMAINS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="${item%%:*}"
      value="$(eval 'printf "%s" "${'"$var"':-}"')"
      [[ -n "$value" ]] || fail "Estado local incompleto para atualizar $APP_LABEL: $var ausente."
      render_args+=("$var" "$value")
    done
  fi

  if [[ -n "$APP_INPUTS" ]]; then
    appdef_split_semicolons "$APP_INPUTS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="$(printf '%s' "$item" | awk -F: '{print $1}')"
      value="$(eval 'printf "%s" "${'"$var"':-}"')"
      render_args+=("$var" "$value")
    done
  fi

  if [[ -n "$APP_SECRETS" ]]; then
    appdef_split_semicolons "$APP_SECRETS"
    for item in "${__appdef_split_result[@]}"; do
      [[ -n "$item" ]] || continue
      var="${item%%:*}"
      value="$(eval 'printf "%s" "${'"$var"':-}"')"
      [[ -n "$value" ]] || fail "Estado local incompleto para atualizar $APP_LABEL: $var ausente."
      render_args+=("$var" "$value")
    done
  fi

  if [[ "$APP_NEEDS_POSTGRES" == "true" ]]; then
    local pg_file pg_host pg_pass
    pg_file="$(recipe_postgres_default_file)"
    pg_host="$(state_get POSTGRES_HOST "$pg_file")"
    pg_pass="$(state_get POSTGRES_PASSWORD "$pg_file")"
    render_args+=(POSTGRES_HOST "$pg_host" POSTGRES_PASSWORD "$pg_pass" POSTGRES_DATABASE "${POSTGRES_DATABASE:-}")
  fi

  [[ "$APP_NEEDS_REDIS" == "true" ]] && render_args+=(REDIS_PASSWORD "${REDIS_PASSWORD:-}")

  stack_render "$(appdef_template_path "$slug")" "$stack_file" "${render_args[@]}"
  recipe_update_apply_stack "$STACK_NAME" "$stack_file"
  state_set APP_IMAGE "$app_image" "$app_file"
}

recipe_update_installed_tool() {
  installer_header
  dependencies_require_base

  if [[ ! -s "$STATE_DIR/apps.tsv" ]]; then
    ui_warn "Nenhuma ferramenta instalada foi encontrada no inventário local."
    ui_pause
    return 0
  fi

  local -a items=()
  local app_name stack_name app_type domain desc
  while IFS=$'\t' read -r app_name stack_name app_type domain; do
    [[ -n "$app_name" ]] || continue
    case "$app_type" in
      base)
        if [[ "$app_name" == "portainer" ]]; then
          desc="Portainer||Reimplanta a stack e permite trocar entre LTS e STS."
        elif [[ "$app_name" == "traefik" ]]; then
          desc="Traefik||Reimplanta a versão testada atual do proxy reverso."
        else
          continue
        fi
        ;;
      postgres)
        desc="PostgreSQL||Reimplanta a stack e aplica a tag testada escolhida."
        ;;
      redis)
        desc="Redis||Reimplanta a stack e reaplica a tag testada escolhida."
        ;;
      n8n)
        desc="n8n||Reimplanta editor, webhook, worker e runners com a versão testada."
        ;;
      uptime-kuma)
        desc="Uptime Kuma||Reimplanta a stack e permite alternar entre v1 e v2."
        ;;
      evolution-api)
        desc="Evolution API||Reimplanta a stack com a tag testada da API."
        ;;
      *)
        if [[ -f "$VPS_INSTALLER_SOURCE_DIR/apps/$app_type/app.env" ]]; then
          desc="$(appdef_label_or_default "$app_type" "$app_name")||Reimplanta a stack com a tag testada escolhida."
        else
          continue
        fi
        ;;
    esac
    items+=("$app_name" "$desc")
  done < "$STATE_DIR/apps.tsv"

  [[ "${#items[@]}" -gt 0 ]] || {
    ui_warn "Ainda não há stacks suportadas para atualização por este menu."
    ui_pause
    return 0
  }

  local selected
  selected="$(ui_menu "Atualizar ferramenta instalada" "${items[@]}" "0" "Voltar||Retorna ao menu principal.")"
  [[ -n "$selected" && "$selected" != "0" ]] || return 0

  local app_file="$APP_STATE_DIR/${selected}.env"
  [[ -f "$app_file" ]] || fail "Arquivo de estado não encontrado: $app_file"
  state_source "$app_file"

  case "$APP_TYPE" in
    base)
      case "$selected" in
        traefik) recipe_update_traefik ;;
        portainer) recipe_update_portainer ;;
        *) fail "Ferramenta base não suportada: $selected" ;;
      esac
      ;;
    postgres) recipe_update_postgres "$app_file" ;;
    redis) recipe_update_redis "$app_file" ;;
    n8n) recipe_update_n8n "$app_file" ;;
    uptime-kuma) recipe_update_uptime_kuma "$app_file" ;;
    evolution-api) recipe_update_evolution_api "$app_file" ;;
    *)
      if [[ -f "$VPS_INSTALLER_SOURCE_DIR/apps/$APP_TYPE/app.env" ]]; then
        recipe_update_generic "$app_file"
      else
        fail "Tipo de aplicação não suportado para atualização: $APP_TYPE"
      fi
      ;;
  esac

  ui_pause
}