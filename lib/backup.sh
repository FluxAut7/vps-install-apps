#!/usr/bin/env bash

backup_export() {
  state_init
  local pass pass2 out tmp
  pass="$(ui_password "Senha para criptografar o backup")"
  pass2="$(ui_password "Confirme a senha")"
  [[ "$pass" == "$pass2" ]] || fail "Senhas nao conferem."
  [[ -n "$pass" ]] || fail "Senha vazia nao permitida."

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/payload"
  cp -a "$STATE_DIR" "$tmp/payload/state"
  cp -a "$STACKS_DIR" "$tmp/payload/stacks"
  cat > "$tmp/payload/manifest.env" <<EOF
BACKUP_FORMAT=1
CREATED_AT=$(date -Iseconds)
HOSTNAME=$(hostname)
DATA_SCOPE=config-and-credentials
EOF

  out="$BACKUP_DIR/vps-installer-$(date +%Y-%m-%d-%H%M%S).enc"
  tar -C "$tmp/payload" -czf "$tmp/backup.tar.gz" .
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 \
    -in "$tmp/backup.tar.gz" -out "$out" -pass "pass:$pass"
  chmod 600 "$out"
  ui_success "Backup exportado: $out"
  ui_warn "Dados/volumes/bancos nao foram incluidos neste backup."
}

backup_list() {
  state_init
  if ! compgen -G "$BACKUP_DIR/*.enc" >/dev/null; then
    echo "Nenhum backup encontrado em $BACKUP_DIR"
    return 0
  fi
  ls -lh "$BACKUP_DIR"/*.enc
}

backup_validate_file() {
  local file="$1"
  local pass="$2"
  local tmp
  [[ -f "$file" ]] || fail "Backup nao encontrado: $file"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "$file" -out "$tmp/backup.tar.gz" -pass "pass:$pass" >/dev/null 2>&1 \
    || fail "Nao foi possivel descriptografar o backup."
  tar -tzf "$tmp/backup.tar.gz" | grep -q './manifest.env' || fail "Manifesto nao encontrado no backup."
  ui_success "Backup valido."
}

backup_validate_interactive() {
  local file pass
  file="$(ui_input "Caminho do backup .enc" "")"
  pass="$(ui_password "Senha do backup")"
  backup_validate_file "$file" "$pass"
}

backup_apply_domain_change() {
  local root="$1"
  local mode="$2"

  case "$mode" in
    keep) return 0 ;;
    base)
      local old_base new_base
      old_base="$(ui_input "Dominio base antigo, ex: antigo.com.br" "")"
      new_base="$(ui_input "Dominio base novo, ex: novo.com.br" "")"
      [[ -n "$old_base" && -n "$new_base" ]] || fail "Dominios base invalidos."
      find "$root" -type f \( -name '*.env' -o -name '*.yml' \) -print0 \
        | xargs -0 sed -i "s|$(stack_sed_escape "$old_base")|$(stack_sed_escape "$new_base")|g"
      ;;
    review)
      local app_file old_domain new_domain
      for app_file in "$root/state/apps/"*.env; do
        [[ -f "$app_file" ]] || continue
        old_domain="$(state_get APP_DOMAIN "$app_file" || true)"
        [[ -n "$old_domain" ]] || continue
        new_domain="$(ui_input "Novo dominio para $old_domain" "$old_domain")"
        [[ "$new_domain" == "$old_domain" ]] && continue
        find "$root" -type f \( -name '*.env' -o -name '*.yml' \) -print0 \
          | xargs -0 sed -i "s|$(stack_sed_escape "$old_domain")|$(stack_sed_escape "$new_domain")|g"
      done
      ;;
  esac
}

backup_import() {
  state_init
  portainer_require_config

  local file pass tmp mode
  file="$(ui_input "Caminho do backup .enc" "")"
  pass="$(ui_password "Senha do backup")"
  [[ -f "$file" ]] || fail "Backup nao encontrado: $file"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
    -in "$file" -out "$tmp/backup.tar.gz" -pass "pass:$pass" >/dev/null 2>&1 \
    || fail "Nao foi possivel descriptografar o backup."
  mkdir -p "$tmp/payload"
  tar -C "$tmp/payload" -xzf "$tmp/backup.tar.gz"
  [[ -f "$tmp/payload/manifest.env" ]] || fail "Manifesto nao encontrado no backup."

  mode="$(ui_menu "Dominios no import" \
    "keep" "Manter dominios originais" \
    "base" "Trocar dominio base" \
    "review" "Revisar dominio por dominio")"
  [[ -n "$mode" ]] || mode="keep"
  backup_apply_domain_change "$tmp/payload" "$mode"

  if ! ui_confirm "Importar estado e recriar stacks nesta VPS?"; then
    ui_warn "Import cancelado."
    return 0
  fi

  cp "$STATE_DIR/portainer.env" "$tmp/current-portainer.env"
  cp -a "$tmp/payload/state/." "$STATE_DIR/"
  cp "$tmp/current-portainer.env" "$STATE_DIR/portainer.env"
  cp -a "$tmp/payload/stacks/." "$STACKS_DIR/"

  local imported_network
  imported_network="$(state_get NETWORK_NAME "$STATE_DIR/config.env" || true)"
  if [[ -n "$imported_network" ]]; then
    system_ensure_network "$imported_network" || true
  fi
  chmod -R go-rwx "$STATE_DIR" "$BACKUP_DIR" "$STACKS_DIR" 2>/dev/null || true

  local app_file app_name stack_name stack_file
  for app_file in "$APP_STATE_DIR/"*.env; do
    [[ -f "$app_file" ]] || continue
    app_name="$(state_get APP_NAME "$app_file")"
    stack_name="$(state_get STACK_NAME "$app_file")"
    stack_file="$(state_get STACK_FILE "$app_file")"
    [[ -f "$stack_file" ]] || stack_file="$STACKS_DIR/${stack_name}.yml"
    if portainer_stack_exists "$stack_name"; then
      ui_warn "Stack ja existe, pulando: $stack_name"
      continue
    fi
    portainer_deploy_stack "$stack_name" "$stack_file"
    ui_success "Importado: $app_name"
  done
}
