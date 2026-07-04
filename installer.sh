#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export VPS_INSTALLER_SOURCE_DIR="$SCRIPT_DIR"

# shellcheck source=lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/state.sh
. "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/system.sh
. "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/dns.sh
. "$SCRIPT_DIR/lib/dns.sh"
# shellcheck source=lib/stack.sh
. "$SCRIPT_DIR/lib/stack.sh"
# shellcheck source=lib/portainer.sh
. "$SCRIPT_DIR/lib/portainer.sh"
# shellcheck source=lib/backup.sh
. "$SCRIPT_DIR/lib/backup.sh"
# shellcheck source=lib/dependencies.sh
. "$SCRIPT_DIR/lib/dependencies.sh"
# shellcheck source=lib/catalog.sh
. "$SCRIPT_DIR/lib/catalog.sh"
# shellcheck source=lib/appdef.sh
. "$SCRIPT_DIR/lib/appdef.sh"

# shellcheck source=recipes/base.sh
. "$SCRIPT_DIR/recipes/base.sh"
# shellcheck source=recipes/postgres.sh
. "$SCRIPT_DIR/recipes/postgres.sh"
# shellcheck source=recipes/redis.sh
. "$SCRIPT_DIR/recipes/redis.sh"
# shellcheck source=recipes/n8n.sh
. "$SCRIPT_DIR/recipes/n8n.sh"
# shellcheck source=recipes/uptime-kuma.sh
. "$SCRIPT_DIR/recipes/uptime-kuma.sh"
# shellcheck source=recipes/evolution-api.sh
. "$SCRIPT_DIR/recipes/evolution-api.sh"
# shellcheck source=recipes/update.sh
. "$SCRIPT_DIR/recipes/update.sh"
# shellcheck source=recipes/generic.sh
. "$SCRIPT_DIR/recipes/generic.sh"

installer_header() {
  ui_clear
  if ui_has_dialog; then
    return 0
  fi
  ui_title "VPS Installer" "Docker Swarm • Traefik • Portainer • Apps open source"
  ui_hint "Fluxo guiado para preparar a VPS, instalar ferramentas e manter o inventário local."
  echo
}

installer_tool_label() {
  local app_name="$1"
  local app_type="$2"
  case "$app_type:$app_name" in
    base:traefik) printf '%s' 'Traefik' ;;
    base:portainer) printf '%s' 'Portainer' ;;
    postgres:*) printf '%s' 'PostgreSQL' ;;
    redis:*) printf '%s' 'Redis' ;;
    n8n:*) printf '%s' 'n8n' ;;
    uptime-kuma:*) printf '%s' 'Uptime Kuma' ;;
    evolution-api:*) printf '%s' 'Evolution API' ;;
    *) printf '%s' "$(appdef_label_or_default "$app_type" "$app_name")" ;;
  esac
}

installer_tool_version() {
  local app_file="$1"
  local app_name="$2"
  local app_type="$3"
  [[ -f "$app_file" ]] || return 0
  state_source "$app_file"

  case "$app_type:$app_name" in
    base:portainer) printf '%s' "${PORTAINER_CHANNEL:-${APP_IMAGE##*:}}" ;;
    base:traefik) printf '%s' "${TRAEFIK_IMAGE##*:}" ;;
    postgres:*) printf '%s' "${POSTGRES_TAG:-${APP_IMAGE##*:}}" ;;
    redis:*) printf '%s' "${REDIS_TAG:-${APP_IMAGE##*:}}" ;;
    n8n:*) printf '%s' "${N8N_VERSION:-${APP_IMAGE##*:}}" ;;
    uptime-kuma:*) printf 'v%s' "${UPTIME_KUMA_MAJOR_VERSION:-${APP_IMAGE##*:}}" ;;
    evolution-api:*) printf '%s' "${EVOLUTION_TAG:-${APP_IMAGE##*:}}" ;;
    *) printf '%s' "${APP_IMAGE##*:}" ;;
  esac
}

installer_stack_usage_text() {
  local usage_file="$1"
  local stack_name="$2"
  [[ -f "$usage_file" ]] || {
    printf '%s' 'sem leitura de consumo'
    return 0
  }

  local line containers cpu mem
  line="$(awk -F '\t' -v stack="$stack_name" '$1 == stack { print $2 "\t" $3 "\t" $4; exit }' "$usage_file")"
  if [[ -z "$line" ]]; then
    printf '%s' 'sem contêiner ativo no momento'
    return 0
  fi

  containers="${line%%$'\t'*}"
  line="${line#*$'\t'}"
  cpu="${line%%$'\t'*}"
  mem="${line#*$'\t'}"
  printf '%s cont. | CPU %s%% | RAM %s' "$containers" "$cpu" "$(system_format_mib "$mem")"
}

installer_live_stack_names() {
  command -v docker >/dev/null 2>&1 || return 0
  docker stack ls --format '{{.Name}}' 2>/dev/null || true
}

installer_inventory_stack_names() {
  [[ -s "$STATE_DIR/apps.tsv" ]] || return 0
  awk -F '\t' '{ print $2 }' "$STATE_DIR/apps.tsv" | awk 'NF' | sort -u
}

installer_join_lines() {
  awk 'NF { out = out (out ? ", " : "") $0 } END { print out }'
}

installer_count_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

installer_live_stack_count() {
  installer_live_stack_names | installer_count_lines
}

installer_inventory_count() {
  installer_inventory_stack_names | installer_count_lines
}

installer_untracked_stack_line() {
  command -v docker >/dev/null 2>&1 || return 0
  local inventory_file live_file diff_file
  inventory_file="$(mktemp "$RUN_DIR/inventory-stacks.XXXXXX")"
  live_file="$(mktemp "$RUN_DIR/live-stacks.XXXXXX")"
  diff_file="$(mktemp "$RUN_DIR/untracked-stacks.XXXXXX")"

  installer_inventory_stack_names > "$inventory_file"
  installer_live_stack_names | sort -u > "$live_file"
  comm -23 "$live_file" "$inventory_file" > "$diff_file" || true

  if [[ -s "$diff_file" ]]; then
    installer_join_lines < "$diff_file"
  fi

  rm -f "$inventory_file" "$live_file" "$diff_file"
}

installer_untracked_stack_count() {
  command -v docker >/dev/null 2>&1 || {
    printf '0'
    return 0
  }

  local inventory_file live_file diff_file count
  inventory_file="$(mktemp "$RUN_DIR/inventory-count.XXXXXX")"
  live_file="$(mktemp "$RUN_DIR/live-count.XXXXXX")"
  diff_file="$(mktemp "$RUN_DIR/untracked-count.XXXXXX")"

  installer_inventory_stack_names > "$inventory_file"
  installer_live_stack_names | sort -u > "$live_file"
  comm -23 "$live_file" "$inventory_file" > "$diff_file" || true
  count="$(installer_count_lines < "$diff_file")"

  rm -f "$inventory_file" "$live_file" "$diff_file"
  printf '%s' "$count"
}

installer_has_portainer() {
  [[ -f "$APP_STATE_DIR/portainer.env" ]] || [[ -n "$(state_get PORTAINER_URL "$STATE_DIR/portainer.env" || true)" ]]
}

installer_stack_exists() {
  local stack_name="$1"
  installer_live_stack_names | grep -Fxq "$stack_name"
}

installer_extract_host_from_rule() {
  local rule="$1"
  printf '%s' "$rule" | awk -F'`' '/Host\(`/ { print $2; exit }'
}

installer_service_labels_json() {
  local service_name="$1"
  docker service inspect "$service_name" --format '{{json .Spec.Labels}}' 2>/dev/null || printf '{}'
}

installer_service_image() {
  local service_name="$1"
  docker service inspect "$service_name" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' 2>/dev/null | sed 's/@.*$//'
}

installer_service_args_lines() {
  local service_name="$1"
  docker service inspect "$service_name" --format '{{json .Spec.TaskTemplate.ContainerSpec.Args}}' 2>/dev/null \
    | jq -r '.[]?'
}

installer_detect_existing_base() {
  command -v docker >/dev/null 2>&1 || return 1
  installer_stack_exists traefik || return 1
  installer_stack_exists portainer || return 1
  return 0
}

installer_detect_existing_network_name() {
  local network_name
  network_name="$(installer_service_labels_json portainer_portainer | jq -r '."traefik.docker.network" // empty')"
  if [[ -n "$network_name" ]]; then
    printf '%s' "$network_name"
    return 0
  fi

  installer_service_args_lines traefik_traefik | sed -n 's/^--providers.swarm.network=//p' | head -n 1
}

installer_detect_existing_ssl_email() {
  installer_service_args_lines traefik_traefik | sed -n 's/^--certificatesresolvers\.letsencryptresolver\.acme\.email=//p' | head -n 1
}

installer_detect_existing_portainer_domain() {
  local rule
  rule="$(installer_service_labels_json portainer_portainer | jq -r '."traefik.http.routers.portainer.rule" // empty')"
  [[ -n "$rule" ]] || return 0
  installer_extract_host_from_rule "$rule"
}

installer_detect_existing_portainer_channel() {
  local image tag
  image="$(installer_service_image portainer_portainer)"
  tag="${image##*:}"
  case "$tag" in
    lts|sts) printf '%s' "$tag" ;;
    *) printf '' ;;
  esac
}

installer_import_existing_base() {
  local network_name ssl_email portainer_domain portainer_channel traefik_image portainer_image portainer_agent_image
  network_name="$(installer_detect_existing_network_name)"
  ssl_email="$(installer_detect_existing_ssl_email)"
  portainer_domain="$(installer_detect_existing_portainer_domain)"
  portainer_channel="$(installer_detect_existing_portainer_channel)"
  traefik_image="$(installer_service_image traefik_traefik)"
  portainer_image="$(installer_service_image portainer_portainer)"
  portainer_agent_image="$(installer_service_image portainer_agent)"

  [[ -n "$network_name" ]] && state_set NETWORK_NAME "$network_name"
  [[ -n "$ssl_email" ]] && state_set SSL_EMAIL "$ssl_email"
  [[ -n "$portainer_domain" ]] && state_set PORTAINER_DOMAIN "$portainer_domain"
  [[ -n "$portainer_channel" ]] && state_set PORTAINER_CHANNEL "$portainer_channel"
  [[ -n "$traefik_image" ]] && state_set TRAEFIK_IMAGE "$traefik_image"
  [[ -n "$portainer_image" ]] && state_set PORTAINER_IMAGE "$portainer_image"
  [[ -n "$portainer_agent_image" ]] && state_set PORTAINER_AGENT_IMAGE "$portainer_agent_image"

  state_register_app "traefik" "traefik" "base" "" "$traefik_image" ""
  [[ -n "$traefik_image" ]] && state_set TRAEFIK_IMAGE "$traefik_image" "$APP_STATE_DIR/traefik.env"

  state_register_app "portainer" "portainer" "base" "$portainer_domain" "$portainer_image" ""
  [[ -n "$portainer_channel" ]] && state_set PORTAINER_CHANNEL "$portainer_channel" "$APP_STATE_DIR/portainer.env"
  [[ -n "$portainer_agent_image" ]] && state_set PORTAINER_AGENT_IMAGE "$portainer_agent_image" "$APP_STATE_DIR/portainer.env"
}

installer_bind_existing_portainer_credentials() {
  local detected_url default_url url user pass
  detected_url="$(state_get PORTAINER_URL "$STATE_DIR/portainer.env" || true)"
  if [[ -z "$detected_url" ]]; then
    local detected_domain
    detected_domain="$(state_get PORTAINER_DOMAIN "$STATE_DIR/config.env" || true)"
    if [[ -n "$detected_domain" ]]; then
      detected_url="https://$detected_domain"
    else
      detected_url="http://127.0.0.1:9000"
    fi
  fi

  default_url="$detected_url"
  url="$(ui_input "URL do Portainer" "$default_url")"
  user="$(ui_input "Usuário do Portainer" "$(state_get PORTAINER_USER "$STATE_DIR/portainer.env" || true)")"
  pass="$(ui_password "Senha do Portainer")"
  [[ -n "$url" && -n "$user" && -n "$pass" ]] || {
    ui_warn "Vínculo com o Portainer ignorado por credenciais incompletas."
    return 0
  }

  state_set PORTAINER_URL "$url" "$STATE_DIR/portainer.env"
  state_set PORTAINER_API_URL "http://127.0.0.1:9000" "$STATE_DIR/portainer.env"
  state_set PORTAINER_USER "$user" "$STATE_DIR/portainer.env"
  state_set PORTAINER_PASSWORD "$pass" "$STATE_DIR/portainer.env"
  chmod 600 "$STATE_DIR/portainer.env"

  if portainer_login >/dev/null 2>&1; then
    ui_success "Portainer vinculado ao instalador."
    return 0
  fi

  ui_warn "Falha ao autenticar via API local. Tentando URL detectada..."
  state_set PORTAINER_API_URL "$url" "$STATE_DIR/portainer.env"
  portainer_login >/dev/null
  ui_success "Portainer vinculado ao instalador."
}

installer_import_existing_base_interactive() {
  state_init
  installer_detect_existing_base || {
    ui_warn "Nenhuma base existente com Traefik e Portainer foi detectada nesta VPS."
    ui_pause
    return 0
  }

  local network_name ssl_email portainer_domain portainer_channel traefik_image portainer_image
  network_name="$(installer_detect_existing_network_name)"
  ssl_email="$(installer_detect_existing_ssl_email)"
  portainer_domain="$(installer_detect_existing_portainer_domain)"
  portainer_channel="$(installer_detect_existing_portainer_channel)"
  traefik_image="$(installer_service_image traefik_traefik)"
  portainer_image="$(installer_service_image portainer_portainer)"

  local summary
  summary="Base existente detectada nesta VPS.

Esta etapa importa a base para o inventário local.
As credenciais do Portainer são opcionais neste momento e só serão necessárias para ações via API, como deploy, update, remoção e restore.

Traefik: sim
Portainer: sim
Rede detectada: ${network_name:-não identificada}
Email SSL: ${ssl_email:-não identificado}
Domínio do Portainer: ${portainer_domain:-não identificado}
Canal do Portainer: ${portainer_channel:-não identificado}
Imagem Traefik: ${traefik_image:-não identificada}
Imagem Portainer: ${portainer_image:-não identificada}

Deseja importar essa base para o inventário do instalador?"

  installer_header
  ui_confirm_values "Importar base existente" "$summary" || return 0

  installer_import_existing_base
  state_set FIRST_ACCESS_BASE_IMPORT_CHECKED 1
  ui_success "Base importada para o inventário local."

  if ui_confirm "Deseja vincular agora as credenciais do Portainer ao instalador para liberar ações via API?"; then
    installer_bind_existing_portainer_credentials
  else
    ui_warn "O Portainer foi importado para o inventário. O vínculo de credenciais ficou pendente e pode ser feito depois no menu Portainer."
  fi

  ui_pause
}

installer_first_access_existing_base_flow() {
  [[ "$(state_get FIRST_ACCESS_BASE_IMPORT_CHECKED "$STATE_DIR/config.env" || true)" == "1" ]] && return 0

  if [[ "$(installer_inventory_count)" -gt 0 ]]; then
    state_set FIRST_ACCESS_BASE_IMPORT_CHECKED 1
    return 0
  fi

  if ! installer_detect_existing_base; then
    state_set FIRST_ACCESS_BASE_IMPORT_CHECKED 1
    return 0
  fi

  installer_import_existing_base_interactive
  state_set FIRST_ACCESS_BASE_IMPORT_CHECKED 1
}

installer_untracked_stack_names() {
  command -v docker >/dev/null 2>&1 || return 0
  local inventory_file live_file diff_file
  inventory_file="$(mktemp "$RUN_DIR/inventory-lines.XXXXXX")"
  live_file="$(mktemp "$RUN_DIR/live-lines.XXXXXX")"
  diff_file="$(mktemp "$RUN_DIR/untracked-lines.XXXXXX")"

  installer_inventory_stack_names > "$inventory_file"
  installer_live_stack_names | sort -u > "$live_file"
  comm -23 "$live_file" "$inventory_file" > "$diff_file" || true
  cat "$diff_file"
  rm -f "$inventory_file" "$live_file" "$diff_file"
}

installer_service_env_lines() {
  local service_name="$1"
  docker service inspect "$service_name" --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}' 2>/dev/null | jq -r '.[]?'
}

installer_service_env_value() {
  local service_name="$1"
  local key="$2"
  installer_service_env_lines "$service_name" | sed -n "s/^${key}=//p" | head -n 1
}

installer_stack_services_lines() {
  local stack_name="$1"
  docker stack services "$stack_name" --format '{{.Name}}' 2>/dev/null || true
}

installer_stack_first_service_by_image() {
  local stack_name="$1"
  local image_pattern="$2"
  local service_name image
  while read -r service_name; do
    [[ -n "$service_name" ]] || continue
    image="$(installer_service_image "$service_name")"
    if [[ "$image" == *"$image_pattern"* ]]; then
      printf '%s' "$service_name"
      return 0
    fi
  done < <(installer_stack_services_lines "$stack_name")
}

installer_stack_service_name() {
  local stack_name="$1"
  local suffix="$2"
  local service_name="${stack_name}_${suffix}"
  if docker service inspect "$service_name" >/dev/null 2>&1; then
    printf '%s' "$service_name"
    return 0
  fi
  return 1
}

installer_service_short_name() {
  local stack_name="$1"
  local service_name="$2"
  printf '%s' "${service_name#${stack_name}_}"
}

installer_service_router_domain() {
  local service_name="$1"
  local rule
  rule="$(installer_service_labels_json "$service_name" | jq -r 'to_entries[]? | select(.key | test("^traefik\\.http\\.routers\\..*\\.rule$")) | .value' | head -n 1)"
  [[ -n "$rule" ]] || return 0
  installer_extract_host_from_rule "$rule"
}

installer_url_host() {
  local url="$1"
  printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/]+)/?.*$#\1#'
}

installer_secret_line() {
  local label="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    printf '%s: %s\n' "$label" "$value"
  else
    printf '%s: não detectada\n' "$label"
  fi
}

installer_detect_supported_stack_type() {
  local stack_name="$1"
  local service_name image

  if [[ "$stack_name" == "traefik" || "$stack_name" == "portainer" ]]; then
    printf '%s' 'base'
    return 0
  fi

  while read -r service_name; do
    [[ -n "$service_name" ]] || continue
    image="$(installer_service_image "$service_name")"
    case "$image" in
      *n8nio/n8n*|*n8nio/runners*) printf '%s' 'n8n'; return 0 ;;
      *evoapicloud/evolution-api*) printf '%s' 'evolution-api'; return 0 ;;
      *louislam/uptime-kuma*) printf '%s' 'uptime-kuma'; return 0 ;;
    esac
  done < <(installer_stack_services_lines "$stack_name")

  service_name="$(installer_stack_first_service_by_image "$stack_name" 'postgres:')"
  if [[ -n "$service_name" ]]; then
    printf '%s' 'postgres'
    return 0
  fi

  service_name="$(installer_stack_first_service_by_image "$stack_name" 'redis:')"
  if [[ -n "$service_name" ]]; then
    printf '%s' 'redis'
    return 0
  fi

  printf ''
}

installer_import_existing_postgres_stack() {
  local stack_name="$1"
  local service_name image tag host password app_file summary
  service_name="$(installer_stack_first_service_by_image "$stack_name" 'postgres:')"
  [[ -n "$service_name" ]] || fail "Serviço PostgreSQL não encontrado na stack: $stack_name"
  image="$(installer_service_image "$service_name")"
  tag="${image##*:}"
  host="$(installer_service_short_name "$stack_name" "$service_name")"
  password="$(installer_service_env_value "$service_name" POSTGRES_PASSWORD)"

  summary="Stack detectada: $stack_name
Tipo: PostgreSQL
Serviço: $service_name
Imagem: ${image:-não identificada}
Host interno: ${host:-não identificado}
$(installer_secret_line 'POSTGRES_PASSWORD' "$password")
Deseja importar esta stack para o inventário do instalador?"

  ui_confirm_values "Importar stack existente" "$summary" || return 0

  state_register_app "$stack_name" "$stack_name" "postgres" "" "$image" ""
  app_file="$APP_STATE_DIR/${stack_name}.env"
  state_set POSTGRES_TAG "$tag" "$app_file"
  state_set POSTGRES_HOST "$host" "$app_file"
  state_set POSTGRES_USER 'postgres' "$app_file"
  [[ -n "$password" ]] && state_set POSTGRES_PASSWORD "$password" "$app_file"
  if [[ -n "$password" ]]; then
    state_set POSTGRES_URL "postgresql://postgres:$password@$host:5432/postgres" "$app_file"
  fi
  ui_success "Stack PostgreSQL importada: $stack_name"
}

installer_import_existing_redis_stack() {
  local stack_name="$1"
  local service_name image tag host password app_file summary
  service_name="$(installer_stack_first_service_by_image "$stack_name" 'redis:')"
  [[ -n "$service_name" ]] || fail "Serviço Redis não encontrado na stack: $stack_name"
  image="$(installer_service_image "$service_name")"
  tag="${image##*:}"
  host="$(installer_service_short_name "$stack_name" "$service_name")"
  password="$(installer_service_args_lines "$service_name" | sed -n 's/^--requirepass$//p')"
  if [[ -z "$password" ]]; then
    password="$(installer_service_args_lines "$service_name" | awk 'prev=="--requirepass" { print; exit } { prev=$0 }')"
  fi

  summary="Stack detectada: $stack_name
Tipo: Redis
Serviço: $service_name
Imagem: ${image:-não identificada}
Host interno: ${host:-não identificado}
$(installer_secret_line 'REDIS_PASSWORD' "$password")
Deseja importar esta stack para o inventário do instalador?"

  ui_confirm_values "Importar stack existente" "$summary" || return 0

  state_register_app "$stack_name" "$stack_name" "redis" "" "$image" ""
  app_file="$APP_STATE_DIR/${stack_name}.env"
  state_set REDIS_TAG "$tag" "$app_file"
  state_set REDIS_HOST "$host" "$app_file"
  [[ -n "$password" ]] && state_set REDIS_PASSWORD "$password" "$app_file"
  if [[ -n "$password" ]]; then
    state_set REDIS_URL "redis://:$password@$host:6379/0" "$app_file"
  fi
  ui_success "Stack Redis importada: $stack_name"
}

installer_import_existing_uptime_kuma_stack() {
  local stack_name="$1"
  local service_name image domain major app_file summary
  service_name="$(installer_stack_first_service_by_image "$stack_name" 'louislam/uptime-kuma')"
  [[ -n "$service_name" ]] || fail "Serviço Uptime Kuma não encontrado na stack: $stack_name"
  image="$(installer_service_image "$service_name")"
  domain="$(installer_service_router_domain "$service_name")"
  major="${image##*:}"

  summary="Stack detectada: $stack_name
Tipo: Uptime Kuma
Serviço: $service_name
Imagem: ${image:-não identificada}
Domínio: ${domain:-não detectado}
Deseja importar esta stack para o inventário do instalador?"

  ui_confirm_values "Importar stack existente" "$summary" || return 0

  state_register_app "$stack_name" "$stack_name" "uptime-kuma" "$domain" "$image" ""
  app_file="$APP_STATE_DIR/${stack_name}.env"
  state_set UPTIME_KUMA_DOMAIN "$domain" "$app_file"
  state_set UPTIME_KUMA_IMAGE "$image" "$app_file"
  state_set UPTIME_KUMA_MAJOR_VERSION "$major" "$app_file"
  ui_success "Stack Uptime Kuma importada: $stack_name"
}

installer_import_existing_n8n_stack() {
  local stack_name="$1"
  local editor_service webhook_service runners_service image runners_image editor_domain webhook_domain version database encryption_key runners_token redis_password app_file summary
  editor_service="$(installer_stack_service_name "$stack_name" editor || true)"
  webhook_service="$(installer_stack_service_name "$stack_name" webhook || true)"
  runners_service="$(installer_stack_service_name "$stack_name" runners || true)"
  [[ -n "$editor_service" ]] || editor_service="$(installer_stack_first_service_by_image "$stack_name" 'n8nio/n8n')"
  [[ -n "$editor_service" ]] || fail "Serviço principal do n8n não encontrado na stack: $stack_name"

  image="$(installer_service_image "$editor_service")"
  runners_image="$(installer_service_image "$runners_service")"
  version="${image##*:}"
  editor_domain="$(installer_service_router_domain "$editor_service")"
  [[ -n "$editor_domain" ]] || editor_domain="$(installer_service_env_value "$editor_service" N8N_HOST)"
  webhook_domain="$(installer_service_router_domain "$webhook_service")"
  if [[ -z "$webhook_domain" ]]; then
    webhook_domain="$(installer_url_host "$(installer_service_env_value "$editor_service" WEBHOOK_URL)")"
  fi
  database="$(installer_service_env_value "$editor_service" DB_POSTGRESDB_DATABASE)"
  encryption_key="$(installer_service_env_value "$editor_service" N8N_ENCRYPTION_KEY)"
  runners_token="$(installer_service_env_value "$editor_service" N8N_RUNNERS_AUTH_TOKEN)"
  [[ -n "$runners_token" ]] || runners_token="$(installer_service_env_value "$runners_service" N8N_RUNNERS_AUTH_TOKEN)"
  redis_password="$(installer_service_env_value "$editor_service" QUEUE_BULL_REDIS_PASSWORD)"

  summary="Stack detectada: $stack_name
Tipo: n8n
Serviço editor: ${editor_service:-não identificado}
Imagem: ${image:-não identificada}
Imagem runners: ${runners_image:-não identificada}
Domínio editor: ${editor_domain:-não detectado}
Domínio webhook: ${webhook_domain:-não detectado}
Banco da fila: ${database:-não detectado}
$(installer_secret_line 'N8N_ENCRYPTION_KEY' "$encryption_key")$(installer_secret_line 'N8N_RUNNERS_AUTH_TOKEN' "$runners_token")$(installer_secret_line 'REDIS_PASSWORD' "$redis_password")
Deseja importar esta stack para o inventário do instalador?"

  ui_confirm_values "Importar stack existente" "$summary" || return 0

  state_register_app "$stack_name" "$stack_name" "n8n" "$editor_domain" "$image" ""
  app_file="$APP_STATE_DIR/${stack_name}.env"
  state_set WEBHOOK_DOMAIN "$webhook_domain" "$app_file"
  state_set N8N_VERSION "$version" "$app_file"
  state_set N8N_IMAGE "$image" "$app_file"
  [[ -n "$runners_image" ]] && state_set N8N_RUNNERS_IMAGE "$runners_image" "$app_file"
  [[ -n "$encryption_key" ]] && state_set N8N_ENCRYPTION_KEY "$encryption_key" "$app_file"
  [[ -n "$runners_token" ]] && state_set N8N_RUNNERS_AUTH_TOKEN "$runners_token" "$app_file"
  [[ -n "$database" ]] && state_set POSTGRES_DATABASE "$database" "$app_file"
  [[ -n "$redis_password" ]] && state_set REDIS_PASSWORD "$redis_password" "$app_file"
  ui_success "Stack n8n importada: $stack_name"
}

installer_import_existing_evolution_stack() {
  local stack_name="$1"
  local api_service image tag domain api_key database redis_password app_file db_uri redis_uri summary
  api_service="$(installer_stack_service_name "$stack_name" api || true)"
  [[ -n "$api_service" ]] || api_service="$(installer_stack_first_service_by_image "$stack_name" 'evoapicloud/evolution-api')"
  [[ -n "$api_service" ]] || fail "Serviço Evolution API não encontrado na stack: $stack_name"

  image="$(installer_service_image "$api_service")"
  tag="${image##*:}"
  domain="$(installer_service_router_domain "$api_service")"
  [[ -n "$domain" ]] || domain="$(installer_url_host "$(installer_service_env_value "$api_service" SERVER_URL)")"
  api_key="$(installer_service_env_value "$api_service" AUTHENTICATION_API_KEY)"
  db_uri="$(installer_service_env_value "$api_service" DATABASE_CONNECTION_URI)"
  database="$(printf '%s' "$db_uri" | sed -E 's#^.*/([^/?]+).*$#\1#')"
  redis_uri="$(installer_service_env_value "$api_service" CACHE_REDIS_URI)"
  redis_password="$(printf '%s' "$redis_uri" | sed -n -E 's#^redis://:([^@]+)@.*$#\1#p')"

  summary="Stack detectada: $stack_name
Tipo: Evolution API
Serviço: ${api_service:-não identificado}
Imagem: ${image:-não identificada}
Domínio: ${domain:-não detectado}
Banco: ${database:-não detectado}
$(installer_secret_line 'EVOLUTION_API_KEY' "$api_key")$(installer_secret_line 'REDIS_PASSWORD' "$redis_password")
Deseja importar esta stack para o inventário do instalador?"

  ui_confirm_values "Importar stack existente" "$summary" || return 0

  state_register_app "$stack_name" "$stack_name" "evolution-api" "$domain" "$image" ""
  app_file="$APP_STATE_DIR/${stack_name}.env"
  state_set EVOLUTION_TAG "$tag" "$app_file"
  [[ -n "$api_key" ]] && state_set EVOLUTION_API_KEY "$api_key" "$app_file"
  [[ -n "$database" ]] && state_set POSTGRES_DATABASE "$database" "$app_file"
  [[ -n "$redis_password" ]] && state_set REDIS_PASSWORD "$redis_password" "$app_file"
  ui_success "Stack Evolution API importada: $stack_name"
}

installer_import_existing_stack_interactive() {
  state_init
  command -v docker >/dev/null 2>&1 || fail "Docker não instalado nesta VPS."

  local -a items=()
  local stack_name stack_type desc
  while read -r stack_name; do
    [[ -n "$stack_name" ]] || continue
    stack_type="$(installer_detect_supported_stack_type "$stack_name")"
    case "$stack_type" in
      postgres) desc="PostgreSQL||Importa a stack e tenta detectar senha do banco." ;;
      redis) desc="Redis||Importa a stack e tenta detectar senha do Redis." ;;
      n8n) desc="n8n||Importa a stack e tenta detectar chaves, token e senha do Redis interno." ;;
      uptime-kuma) desc="Uptime Kuma||Importa a stack e registra domínio e versão." ;;
      evolution-api) desc="Evolution API||Importa a stack e tenta detectar API key e senha do Redis." ;;
      *) continue ;;
    esac
    items+=("$stack_name" "$desc")
  done < <(installer_untracked_stack_names)

  if [[ "${#items[@]}" -eq 0 ]]; then
    installer_header
    ui_warn "Nenhuma stack suportada fora do inventário foi encontrada para importação."
    ui_pause
    return 0
  fi

  local selected stack_type
  selected="$(installer_menu_with_summary "Importar stack existente" "${items[@]}" "0" "Voltar||Retorna ao menu Ferramentas.")"
  [[ -n "$selected" && "$selected" != "0" ]] || return 0

  stack_type="$(installer_detect_supported_stack_type "$selected")"
  case "$stack_type" in
    postgres) installer_import_existing_postgres_stack "$selected" ;;
    redis) installer_import_existing_redis_stack "$selected" ;;
    n8n) installer_import_existing_n8n_stack "$selected" ;;
    uptime-kuma) installer_import_existing_uptime_kuma_stack "$selected" ;;
    evolution-api) installer_import_existing_evolution_stack "$selected" ;;
    *) fail "Tipo de stack não suportado para importação: $selected" ;;
  esac

  ui_pause
}

installer_summary_text() {
  local so_line usage_line stacks_count inventory_count unmanaged_count
  so_line="${VPSI_OS_ID^} ${VPSI_OS_VERSION:-}"

  if command -v docker >/dev/null 2>&1; then
    usage_line="$(system_vps_usage_line)"
    stacks_count="$(installer_live_stack_count)"
    unmanaged_count="$(installer_untracked_stack_count)"
  else
    usage_line="indisponível sem Docker"
    stacks_count="0"
    unmanaged_count="0"
  fi

  inventory_count="$(installer_inventory_count)"

  cat <<EOF
SO: $so_line
Uso: $usage_line
Stacks: $stacks_count
Inventário local: $inventory_count
Não gerenciadas: $unmanaged_count
EOF
}

installer_show_summary() {
  ui_section "Resumo da VPS"
  ui_kv "SO" "${VPSI_OS_ID^} ${VPSI_OS_VERSION:-}"
  if command -v docker >/dev/null 2>&1; then
    ui_kv "Uso" "$(system_vps_usage_line)"
    ui_kv "Stacks" "$(installer_live_stack_count)"
    ui_kv "Inventário local" "$(installer_inventory_count)"
    ui_kv "Não gerenciadas" "$(installer_untracked_stack_count)"
  else
    ui_kv "Uso" "indisponível sem Docker"
    ui_kv "Stacks" "0"
    ui_kv "Inventário local" "$(installer_inventory_count)"
    ui_kv "Não gerenciadas" "0"
  fi
}

installer_menu_with_summary() {
  local title="$1"
  shift

  if ui_has_dialog; then
    ui_menu_with_text "$title" "$(installer_summary_text)" "$@"
    return 0
  fi

  installer_header
  installer_show_summary
  echo
  ui_menu "$title" "$@"
}

installer_show_dashboard() {
  state_init
  installer_show_summary

  echo
  ui_section "Stacks do Docker"
  if command -v docker >/dev/null 2>&1; then
    local live_stacks extra_stacks
    live_stacks="$(installer_live_stack_names | installer_join_lines)"
    extra_stacks="$(installer_untracked_stack_line || true)"
    ui_kv "Detectadas" "${live_stacks:-nenhuma stack detectada}"
    if [[ -n "$extra_stacks" ]]; then
      ui_kv "Fora do inventário" "$extra_stacks"
    fi
  else
    ui_hint "Docker não instalado."
  fi

  echo
  ui_section "Ferramentas instaladas"
  if [[ ! -s "$STATE_DIR/apps.tsv" ]]; then
    ui_hint "Nenhuma ferramenta instalada foi registrada pelo instalador."
    return 0
  fi

  local usage_file=""
  if command -v docker >/dev/null 2>&1; then
    usage_file="$(mktemp "$RUN_DIR/usage-report.XXXXXX")"
    system_collect_stack_usage > "$usage_file" 2>/dev/null || true
  fi

  local app_name stack_name app_type domain app_file label version usage details
  while IFS=$'\t' read -r app_name stack_name app_type domain; do
    [[ -n "$app_name" ]] || continue
    app_file="$APP_STATE_DIR/${app_name}.env"
    label="$(installer_tool_label "$app_name" "$app_type")"
    version="$(installer_tool_version "$app_file" "$app_name" "$app_type")"
    usage="$(installer_stack_usage_text "$usage_file" "$stack_name")"
    printf '  \033[1;93m%-18s\033[0m %s\n' "$label" "$usage" >&2
    details="stack=$stack_name"
    if [[ -n "$version" ]]; then
      details="$details | versão=$version"
    fi
    if [[ -n "$domain" ]]; then
      details="$details | domínio=$domain"
    fi
    printf '      \033[38;5;244m%s\033[0m\n' "$details" >&2
  done < "$STATE_DIR/apps.tsv"

  [[ -n "$usage_file" ]] && rm -f "$usage_file"
}

show_status() {
  installer_header
  state_init
  installer_show_dashboard

  echo
  if command -v docker >/dev/null 2>&1; then
    ui_section "Docker"
    docker --version || true
    docker info --format 'Swarm: {{.Swarm.LocalNodeState}}' 2>/dev/null || true
    echo
    ui_section "Tabela de stacks"
    docker stack ls 2>/dev/null || true
  else
    ui_warn "Docker não instalado."
  fi

  ui_pause
}

installer_stack_volume_names() {
  local stack="$1"
  local -A seen=()
  local vol
  while read -r vol; do
    [[ -n "$vol" ]] || continue
    seen["$vol"]=1
  done < <(docker volume ls --filter "label=com.docker.stack.namespace=$stack" --format '{{.Name}}' 2>/dev/null)

  while read -r vol; do
    [[ -n "$vol" ]] || continue
    seen["$vol"]=1
  done < <(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "^${stack}_")

  local name
  for name in "${!seen[@]}"; do
    printf '%s\n' "$name"
  done | sort -u
}

installer_wait_stack_gone() {
  local stack="$1"
  local timeout="${2:-60}"
  local elapsed=0
  while (( elapsed < timeout )); do
    [[ -z "$(docker ps -q --filter "label=com.docker.stack.namespace=$stack" 2>/dev/null)" ]] && return 0
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

remove_stack_menu() {
  installer_header
  system_require_docker
  portainer_require_config

  local stack
  stack="$(ui_input "Nome da stack para remover" "")"
  [[ -n "$stack" ]] || return 0

  ui_confirm "Remover a stack '$stack'?" || { ui_pause; return 0; }

  portainer_remove_stack "$stack"
  state_remove_app "$stack" || true
  ui_success "Stack removida: $stack"

  ui_info "Aguardando contêineres da stack encerrarem..."
  installer_wait_stack_gone "$stack" 60 || ui_warn "Alguns contêineres ainda podem estar em encerramento."

  local -a volumes=()
  local vol
  while read -r vol; do
    [[ -n "$vol" ]] || continue
    volumes+=("$vol")
  done < <(installer_stack_volume_names "$stack")

  if [[ "${#volumes[@]}" -eq 0 ]]; then
    ui_pause
    return 0
  fi

  ui_section "Volumes de dados encontrados"
  for vol in "${volumes[@]}"; do
    ui_kv "Volume" "$vol"
  done

  if ! ui_confirm "Apagar também os ${#volumes[@]} volumes listados? Esta ação é IRREVERSÍVEL."; then
    ui_pause
    return 0
  fi

  local confirm_name
  confirm_name="$(ui_input "Digite o nome da stack '$stack' para confirmar a exclusão dos dados" "")"
  if [[ "$confirm_name" != "$stack" ]]; then
    ui_warn "Nome não confere. Os volumes NÃO foram apagados."
    ui_pause
    return 0
  fi

  for vol in "${volumes[@]}"; do
    if docker volume rm "$vol" >/dev/null 2>&1; then
      ui_success "Volume removido: $vol"
    else
      ui_warn "Não foi possível remover o volume (pode estar em uso): $vol"
    fi
  done

  ui_pause
}

installer_env_file_keys() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/ { print $1 }' "$file"
}

installer_print_env_file() {
  local file="$1"
  [[ -f "$file" ]] || { ui_warn "Arquivo de credenciais não encontrado: $file"; return 0; }

  # shellcheck disable=SC1090
  (
    . "$file"
    local key value
    while read -r key; do
      [[ -n "$key" ]] || continue
      value="$(eval 'printf "%s" "${'"$key"':-}"')"
      ui_kv "$key" "$value"
    done < <(installer_env_file_keys "$file")
  )
}

installer_show_portainer_credentials() {
  state_init
  installer_header
  installer_has_portainer || {
    ui_warn "Credenciais do Portainer ainda não configuradas."
    ui_pause
    return 0
  }
  ui_warn "As credenciais aparecerão em texto claro na tela a seguir."
  ui_confirm "Continuar?" || return 0
  installer_header
  ui_section "Credenciais: Portainer"
  installer_print_env_file "$STATE_DIR/portainer.env"
  ui_pause
}

installer_show_credentials() {
  state_init
  installer_header

  local -a items=()
  if [[ -s "$STATE_DIR/apps.tsv" ]]; then
    local app_name stack_name app_type domain
    while IFS=$'\t' read -r app_name stack_name app_type domain; do
      [[ -n "$app_name" ]] || continue
      [[ "$app_type" == "base" ]] && continue
      items+=("$app_name" "$(installer_tool_label "$app_name" "$app_type")||stack=$stack_name")
    done < "$STATE_DIR/apps.tsv"
  fi

  if installer_has_portainer; then
    items+=("__portainer__" "Portainer||Credenciais de acesso à API/console do Portainer")
  fi

  if [[ "${#items[@]}" -eq 0 ]]; then
    ui_warn "Nenhuma ferramenta com credenciais registrada no inventário local."
    ui_pause
    return 0
  fi

  local selected
  selected="$(installer_menu_with_summary "Ver credenciais" "${items[@]}" "0" "Voltar||Retorna ao menu anterior.")"
  [[ -n "$selected" && "$selected" != "0" ]] || return 0

  if [[ "$selected" == "__portainer__" ]]; then
    installer_show_portainer_credentials
    return 0
  fi

  ui_warn "As credenciais aparecerão em texto claro na tela a seguir."
  ui_confirm "Continuar?" || return 0

  installer_header
  ui_section "Credenciais: $selected"
  installer_print_env_file "$APP_STATE_DIR/${selected}.env"
  ui_pause
}

portainer_reset_credentials() {
  installer_header
  state_init
  local url user pass
  url="$(ui_input "URL do Portainer, ex: https://portainer.seudomínio.com.br" "$(state_get PORTAINER_URL "$STATE_DIR/portainer.env" || true)")"
  user="$(ui_input "Usuário do Portainer" "$(state_get PORTAINER_USER "$STATE_DIR/portainer.env" || true)")"
  pass="$(ui_password "Senha do Portainer")"
  [[ -n "$url" && -n "$user" && -n "$pass" ]] || fail "Credenciais incompletas."
  state_set PORTAINER_URL "$url" "$STATE_DIR/portainer.env"
  state_set PORTAINER_API_URL "$url" "$STATE_DIR/portainer.env"
  state_set PORTAINER_USER "$user" "$STATE_DIR/portainer.env"
  state_set PORTAINER_PASSWORD "$pass" "$STATE_DIR/portainer.env"
  chmod 600 "$STATE_DIR/portainer.env"
  portainer_login >/dev/null
  ui_success "Credenciais atualizadas e testadas."
  ui_pause
}

backup_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "Backup / Migração" \
      "1" "Exportar configurações e credenciais||Gera um backup criptografado do estado local." \
      "2" "Importar backup nesta VPS||Restaura stacks e credenciais a partir de um arquivo .enc." \
      "3" "Listar backups locais||Mostra os arquivos de backup disponíveis no servidor." \
      "4" "Validar backup||Confere se o arquivo pode ser descriptografado e lido." \
      "0" "Voltar||Retorna ao menu anterior.")"

    case "$choice" in
      1) backup_export; ui_pause ;;
      2) backup_import; ui_pause ;;
      3) backup_list; ui_pause ;;
      4) backup_validate_interactive; ui_pause ;;
      0|"") return 0 ;;
    esac
  done
}

vps_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "VPS" \
      "1" "Preparar VPS||Instala Docker, Swarm, Traefik e Portainer." \
      "2" "Painel detalhado||Mostra Docker, stacks e ferramentas instaladas." \
      "3" "Atualizar pacotes do sistema||Executa apt-get update e apt-get upgrade -y." \
      "4" "Backup / Migração||Exporta, valida e importa o estado da VPS." \
      "5" "Importar base existente||Detecta Traefik e Portainer já instalados e registra a base no inventário. O vínculo de credenciais do Portainer é opcional nesta etapa." \
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) recipe_base_install ;;
      2) show_status ;;
      3) system_upgrade_packages_interactive ;;
      4) backup_menu ;;
      5) installer_import_existing_base_interactive ;;
      0|"") return 0 ;;
    esac
  done
}

tools_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "Ferramentas" \
      "1" "Importar stack existente||Detecta credenciais, senhas e chaves visíveis na stack antes de confirmar a adoção. Não exige login no Portainer." \
      "2" "Instalar PostgreSQL||Cria a stack do banco com volume persistente." \
      "3" "Instalar Redis||Cria a stack do cache e fila com persistência." \
      "4" "Instalar n8n||Publica editor, webhook, worker e runners externos." \
      "5" "Instalar Uptime Kuma||Publica monitoramento com escolha entre v1 e v2." \
      "6" "Instalar Evolution API||Publica a API com Postgres e Redis internos." \
      "7" "Atualizar ferramenta instalada||Reimplanta a stack e aplica a versão testada." \
      "8" "Remover stack||Exclui uma stack pelo Portainer, com opção de apagar os volumes de dados." \
      "9" "Ver credenciais de uma ferramenta||Mostra URLs, usuários e senhas de um app instalado." \
      "10" "Catálogo de ferramentas||Instala apps adicionais definidos por manifesto (MinIO, RabbitMQ, ...)." \
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) installer_import_existing_stack_interactive ;;
      2) recipe_postgres_install ;;
      3) recipe_redis_install ;;
      4) recipe_n8n_install ;;
      5) recipe_uptime_kuma_install ;;
      6) recipe_evolution_install ;;
      7) recipe_update_installed_tool ;;
      8) remove_stack_menu ;;
      9) installer_show_credentials ;;
      10) recipe_generic_catalog_menu ;;
      0|"") return 0 ;;
    esac
  done
}

portainer_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "Portainer" \
      "1" "Redefinir credenciais||Atualiza a autenticação usada pelo instalador." \
      "2" "Remover stack||Exclui uma stack pelo Portainer, com opção de apagar os volumes de dados." \
      "3" "Ver credenciais do Portainer||Mostra URL, usuário e senha usados pelo instalador." \
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) portainer_reset_credentials ;;
      2) remove_stack_menu ;;
      3) installer_show_portainer_credentials ;;
      0|"") return 0 ;;
    esac
  done
}

main_menu() {
  while true; do
    local choice
    if installer_has_portainer; then
      choice="$(installer_menu_with_summary "Menu principal" \
        "1" "VPS||Base da VPS, painel detalhado, pacotes e backup." \
        "2" "Ferramentas||Instalação, atualização e remoção de stacks." \
        "3" "Portainer||Credenciais e operações que dependem da API do Portainer." \
        "0" "Sair||Encerra o instalador.")"
    else
      choice="$(installer_menu_with_summary "Menu principal" \
        "1" "VPS||Base da VPS, painel detalhado, pacotes e backup." \
        "2" "Ferramentas||Instalação, atualização e remoção de stacks." \
        "0" "Sair||Encerra o instalador.")"
    fi

    case "$choice" in
      1) vps_menu ;;
      2) tools_menu ;;
      3)
        if installer_has_portainer; then
          portainer_menu
        fi
        ;;
      0|"") ui_info "Saindo."; exit 0 ;;
    esac
  done
}

main() {
  system_require_root
  system_detect_os
  state_init
  system_install_base_packages
  installer_first_access_existing_base_flow
  main_menu
}

main "$@"