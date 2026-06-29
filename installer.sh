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

installer_header() {
  ui_clear
  ui_title "VPS Installer"
  echo "Instalador interativo para Docker Swarm, Traefik, Portainer e apps de automacao."
  echo
}

show_status() {
  installer_header
  state_init
  echo "Diretorio: $VPSI_HOME"
  echo

  if command -v docker >/dev/null 2>&1; then
    echo "Docker:"
    docker --version || true
    docker info --format 'Swarm: {{.Swarm.LocalNodeState}}' 2>/dev/null || true
    echo
    echo "Stacks:"
    docker stack ls 2>/dev/null || true
  else
    echo "Docker nao instalado."
  fi

  echo
  echo "Apps registrados:"
  state_list_apps || true
  ui_pause
}

remove_stack_menu() {
  installer_header
  system_require_docker
  portainer_require_config

  local stack
  stack="$(ui_input "Nome da stack para remover" "")"
  [[ -n "$stack" ]] || return 0

  if ui_confirm "Remover a stack '$stack'? Volumes persistentes nao serao apagados."; then
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
  url="$(ui_input "URL do Portainer, ex: https://portainer.seudominio.com.br" "$(state_get PORTAINER_URL "$STATE_DIR/portainer.env" || true)")"
  user="$(ui_input "Usuario do Portainer" "$(state_get PORTAINER_USER "$STATE_DIR/portainer.env" || true)")"
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
    installer_header
    local choice
    choice="$(ui_menu "Backup / Migracao" \
      "1" "Exportar configuracoes e credenciais" \
      "2" "Importar backup nesta VPS" \
      "3" "Listar backups locais" \
      "4" "Validar backup" \
      "0" "Voltar")"

    case "$choice" in
      1) backup_export; ui_pause ;;
      2) backup_import; ui_pause ;;
      3) backup_list; ui_pause ;;
      4) backup_validate_interactive; ui_pause ;;
      0|"") return 0 ;;
    esac
  done
}

main_menu() {
  while true; do
    installer_header
    local choice
    choice="$(ui_menu "Menu principal" \
      "1" "Preparar VPS: Docker + Swarm + Traefik + Portainer" \
      "2" "Instalar PostgreSQL" \
      "3" "Instalar Redis" \
      "4" "Instalar n8n" \
      "5" "Instalar Uptime Kuma" \
      "6" "Instalar Evolution API" \
      "7" "Status" \
      "8" "Remover stack" \
      "9" "Resetar credenciais do Portainer" \
      "10" "Backup / Migracao" \
      "11" "Atualizar pacotes da VPS" \
      "0" "Sair")"

    case "$choice" in
      1) recipe_base_install ;;
      2) recipe_postgres_install ;;
      3) recipe_redis_install ;;
      4) recipe_n8n_install ;;
      5) recipe_uptime_kuma_install ;;
      6) recipe_evolution_install ;;
      7) show_status ;;
      8) remove_stack_menu ;;
      9) portainer_reset_credentials ;;
      10) backup_menu ;;
      11) system_upgrade_packages_interactive ;;
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
