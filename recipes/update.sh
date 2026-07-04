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