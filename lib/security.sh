#!/usr/bin/env bash

# Auditoria somente leitura; mudanças no host são sempre confirmadas no menu.

security_ssh_port() {
  local port
  port="$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }' || true)"
  printf '%s' "${port:-22}"
}

security_service_state() {
  local service="$1"
  systemctl is-active --quiet "$service" 2>/dev/null && printf '%s' 'ativo' || printf '%s' 'inativo'
}

security_ufw_status() {
  command -v ufw >/dev/null 2>&1 || { printf '%s' 'não instalado'; return 0; }
  ufw status 2>/dev/null | awk 'NR == 1 { print $2; exit }'
}

security_ssh_setting() {
  local setting="$1"
  sshd -T 2>/dev/null | awk -v key="$setting" '$1 == key { print $2; exit }'
}

security_list_public_ports() {
  ss -lntupH 2>/dev/null | awk '
    $5 ~ /^(0\.0\.0\.0|\[::\]):/ {
      split($5, addr, ":")
      port = addr[length(addr)]
      process = $7
      gsub(/users:\(\(/, "", process)
      gsub(/\).*/, "", process)
      printf "%s/%s %s\n", port, $1, process
    }
  ' | sort -u
}

security_audit() {
  local ssh_port root_login password_auth ufw_state unattended fail2ban apparmor clamav docker_state public_ports
  ssh_port="$(security_ssh_port)"
  root_login="$(security_ssh_setting permitrootlogin)"
  password_auth="$(security_ssh_setting passwordauthentication)"
  ufw_state="$(security_ufw_status)"
  unattended="$(security_service_state unattended-upgrades)"
  fail2ban="$(security_service_state fail2ban)"
  apparmor="$(security_service_state apparmor)"
  clamav="$(security_service_state clamav-freshclam)"
  docker_state="$(security_service_state docker)"
  public_ports="$(security_list_public_ports)"

  ui_section "Auditoria de segurança"
  ui_kv "Firewall (UFW)" "$ufw_state"
  ui_kv "SSH" "porta $ssh_port | root=${root_login:-não detectado} | senha=${password_auth:-não detectado}"
  ui_kv "Atualizações seg." "$unattended"
  ui_kv "Fail2ban" "$fail2ban"
  ui_kv "AppArmor" "$apparmor"
  ui_kv "ClamAV" "$clamav"
  ui_kv "Docker" "$docker_state"

  echo >&2
  ui_section "Portas TCP escutando externamente"
  if [[ -n "$public_ports" ]]; then
    while read -r port; do
      [[ -n "$port" ]] && ui_kv "Aberta" "$port"
    done <<< "$public_ports"
  else
    ui_hint "Nenhuma porta TCP escutando em todas as interfaces foi detectada."
  fi

  echo >&2
  ui_section "Recomendações"
  [[ "$ufw_state" == "active" ]] || ui_warn "Firewall inativo: aplique o baseline para permitir só SSH, HTTP e HTTPS."
  [[ "$root_login" == "no" || "$root_login" == "prohibit-password" ]] || ui_warn "SSH permite login root. Prefira usuário sudo com chave SSH."
  [[ "$password_auth" == "no" ]] || ui_warn "SSH aceita senhas. Migre uma chave SSH testada antes de desabilitar senhas."
  [[ "$unattended" == "ativo" ]] || ui_warn "Atualizações automáticas de segurança não estão ativas."
  [[ "$fail2ban" == "ativo" ]] || ui_warn "Fail2ban não está ativo; tentativas repetidas de login não são bloqueadas."
  [[ "$clamav" == "ativo" ]] || ui_warn "Antivírus não está ativo. Instale o ClamAV e mantenha as assinaturas atualizadas."
  if printf '%s\n' "$public_ports" | grep -q '^9000/'; then
    ui_warn "A porta 9000 do Portainer está escutando. O baseline bloqueia essa regra no UFW e mantém o acesso HTTPS pelo Traefik."
  fi
}

security_apply_baseline() {
  local ssh_port="$1"

  ui_warn "O firewall permitirá SSH ($ssh_port), HTTP (80) e HTTPS (443) e bloqueará a porta direta 9000 do Portainer."
  ui_warn "Confirme que sua sessão SSH atual usa a porta correta antes de continuar."
  ui_confirm "Aplicar o baseline de firewall e proteção contra força bruta?" || return 0

  ui_info "Instalando e configurando UFW, Fail2ban e atualizações de segurança..."
  system_apt_install ufw fail2ban unattended-upgrades >/dev/null
  ufw allow "${ssh_port}/tcp" comment 'SSH administracao' >/dev/null
  ufw allow 80/tcp comment 'Traefik HTTP' >/dev/null
  ufw allow 443/tcp comment 'Traefik HTTPS' >/dev/null
  ufw --force delete allow 9000/tcp >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw --force enable >/dev/null
  systemctl enable --now fail2ban >/dev/null
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

  ui_success "Baseline aplicado. Portas liberadas: SSH $ssh_port, 80 e 443."
  ui_hint "O acesso ao Portainer deve ser feito por HTTPS, através do domínio configurado."
}

security_install_antivirus() {
  ui_info "Instalando ClamAV e baixando assinaturas de ameaças..."
  system_apt_install clamav clamav-freshclam >/dev/null
  systemctl enable --now clamav-freshclam >/dev/null 2>&1 || true
  freshclam --stdout 2>&1 | tail -12 >&2 || ui_warn "A atualização das assinaturas falhou; tente novamente quando a VPS tiver acesso à internet."
  ui_success "ClamAV instalado. As assinaturas serão atualizadas pelo serviço clamav-freshclam."
}

security_scan_paths() {
  local scan_label="$1"
  shift
  local log_file exit_code
  log_file="$LOG_DIR/clamav-$(date +%Y%m%d-%H%M%S).log"
  ui_info "Iniciando varredura: $scan_label. O resultado será salvo em $log_file"
  set +e
  clamscan --recursive --infected --bell --log="$log_file" "$@"
  exit_code=$?
  set -e
  case "$exit_code" in
    0) ui_success "Varredura concluída: nenhuma ameaça encontrada." ;;
    1) ui_warn "Varredura concluída: possível ameaça encontrada. Nenhum arquivo foi removido; revise $log_file." ;;
    *) ui_warn "A varredura terminou com erro (código $exit_code). Consulte $log_file." ;;
  esac
}

security_scan_common_paths() {
  command -v clamscan >/dev/null 2>&1 || { ui_warn "ClamAV não está instalado."; return 1; }
  security_scan_paths "diretórios usuais" /home /root /opt /var/www
}

security_scan_docker_volumes() {
  command -v clamscan >/dev/null 2>&1 || { ui_warn "ClamAV não está instalado."; return 1; }
  [[ -d /var/lib/docker/volumes ]] || { ui_warn "Diretório de volumes Docker não encontrado."; return 0; }
  ui_warn "Volumes podem conter bancos de dados e a varredura pode ser demorada. Nenhum dado será apagado."
  ui_confirm "Verificar também os volumes Docker?" || return 0
  security_scan_paths "volumes Docker" /var/lib/docker/volumes
}

security_show_latest_scan() {
  local log_file
  log_file="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'clamav-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
  [[ -n "$log_file" && -f "$log_file" ]] || { ui_warn "Nenhuma varredura ClamAV foi registrada ainda."; return 0; }
  ui_section "Último relatório ClamAV"
  ui_kv "Arquivo" "$log_file"
  tail -40 "$log_file" >&2
}
