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
    *) printf '%s' "$app_name" ;;
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

remove_stack_menu() {
  installer_header
  system_require_docker
  portainer_require_config

  local stack
  stack="$(ui_input "Nome da stack para remover" "")"
  [[ -n "$stack" ]] || return 0

  if ui_confirm "Remover a stack '$stack'? Volumes persistentes não serão apagados."; then
    portainer_remove_stack "$stack"
    state_remove_app "$stack" || true
    ui_success "Stack removida: $stack"
  fi
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
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) recipe_base_install ;;
      2) show_status ;;
      3) system_upgrade_packages_interactive ;;
      4) backup_menu ;;
      0|"") return 0 ;;
    esac
  done
}

tools_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "Ferramentas" \
      "1" "Instalar PostgreSQL||Cria a stack do banco com volume persistente." \
      "2" "Instalar Redis||Cria a stack do cache e fila com persistência." \
      "3" "Instalar n8n||Publica editor, webhook, worker e runners externos." \
      "4" "Instalar Uptime Kuma||Publica monitoramento com escolha entre v1 e v2." \
      "5" "Instalar Evolution API||Publica a API com Postgres e Redis internos." \
      "6" "Atualizar ferramenta instalada||Reimplanta a stack e aplica a versão testada." \
      "7" "Remover stack||Exclui uma stack pelo Portainer sem apagar volumes." \
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) recipe_postgres_install ;;
      2) recipe_redis_install ;;
      3) recipe_n8n_install ;;
      4) recipe_uptime_kuma_install ;;
      5) recipe_evolution_install ;;
      6) recipe_update_installed_tool ;;
      7) remove_stack_menu ;;
      0|"") return 0 ;;
    esac
  done
}

portainer_menu() {
  while true; do
    local choice
    choice="$(installer_menu_with_summary "Portainer" \
      "1" "Redefinir credenciais||Atualiza a autenticação usada pelo instalador." \
      "2" "Remover stack||Exclui uma stack pelo Portainer sem apagar volumes." \
      "0" "Voltar||Retorna ao menu principal.")"

    case "$choice" in
      1) portainer_reset_credentials ;;
      2) remove_stack_menu ;;
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
        "3" "Portainer||Credenciais e operações ligadas ao Portainer." \
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
  main_menu
}

main "$@"