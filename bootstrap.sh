#!/usr/bin/env bash
set -Eeuo pipefail

# Public bootstrap intended to be served at:
#   https://vps-setup.fluxaut.com.br
#
# Usage:
#   bash <(curl -sSL https://vps-setup.fluxaut.com.br)

PROJECT_NAME="vps-installer"
DEFAULT_ARCHIVE_URL="https://github.com/FluxAut7/vps-install-apps/archive/refs/heads/main.tar.gz"
ARCHIVE_URL="${VPS_INSTALLER_ARCHIVE_URL:-$DEFAULT_ARCHIVE_URL}"

info() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatorio nao encontrado: $1"
}

main() {
  require_command curl
  require_command tar

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  info "Baixando instalador..."
  curl -fsSL "$ARCHIVE_URL" | tar -xz --strip-components=1 -C "$tmp_dir"

  [[ -f "$tmp_dir/installer.sh" ]] || fail "installer.sh nao encontrado no pacote baixado."
  chmod +x "$tmp_dir/installer.sh"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    require_command sudo
    info "Elevando permissao com sudo..."
    sudo -E bash "$tmp_dir/installer.sh" "$@"
    exit $?
  fi

  bash "$tmp_dir/installer.sh" "$@"
}

main "$@"
