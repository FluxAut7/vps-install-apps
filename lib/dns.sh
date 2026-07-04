#!/usr/bin/env bash

VPSI_PUBLIC_IP=""

dns_public_ip() {
  if [[ -n "$VPSI_PUBLIC_IP" ]]; then
    printf '%s' "$VPSI_PUBLIC_IP"
    return 0
  fi

  local ip url
  for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip="$(curl -fsS -4 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      VPSI_PUBLIC_IP="$ip"
      printf '%s' "$ip"
      return 0
    fi
  done

  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    ui_warn "Não foi possível confirmar o IP público via internet; usando IP local ($ip), que pode ser privado."
    VPSI_PUBLIC_IP="$ip"
    printf '%s' "$ip"
    return 0
  fi

  return 1
}

dns_resolve() {
  local domain="$1"
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u
}

dns_is_cloudflare_ip() {
  local ip="$1"
  case "$ip" in
    104.16.*|104.17.*|104.18.*|104.19.*|104.20.*|104.21.*|104.22.*|104.23.*|104.24.*|104.25.*|104.26.*|104.27.*) return 0 ;;
    172.64.*|172.65.*|172.66.*|172.67.*|172.68.*|172.69.*|172.70.*|172.71.*) return 0 ;;
    131.0.72.*|131.0.73.*|131.0.74.*|131.0.75.*) return 0 ;;
    *) return 1 ;;
  esac
}

dns_check_domain() {
  local domain="$1"
  local public_ip resolved ip
  public_ip="$(dns_public_ip)" || return 1
  resolved="$(dns_resolve "$domain")"
  [[ -n "$resolved" ]] || return 1
  while read -r ip; do
    [[ "$ip" == "$public_ip" ]] && return 0
  done <<< "$resolved"
  return 1
}

dns_confirm_domain() {
  local domain="$1"
  local public_ip resolved ip

  public_ip="$(dns_public_ip)" || {
    ui_warn "Não foi possível determinar o IP público da VPS para validar o DNS de '$domain'."
    ui_confirm "Continuar mesmo sem validar o DNS?"
    return $?
  }

  resolved="$(dns_resolve "$domain")"

  if [[ -n "$resolved" ]]; then
    while read -r ip; do
      if [[ "$ip" == "$public_ip" ]]; then
        ui_success "DNS ok: $domain → $ip"
        return 0
      fi
    done <<< "$resolved"

    if dns_is_cloudflare_ip "$(printf '%s\n' "$resolved" | head -n 1)"; then
      ui_warn "'$domain' resolve para um IP da Cloudflare (proxy/nuvem laranja). O desafio HTTP do Let's Encrypt pode falhar; considere usar o modo DNS-only (nuvem cinza) durante a emissão do certificado."
    fi
  fi

  ui_warn "O domínio '$domain' não aponta para esta VPS ($public_ip)."
  if [[ -n "$resolved" ]]; then
    ui_warn "IPs encontrados: $(printf '%s' "$resolved" | tr '\n' ' ')"
  else
    ui_warn "O domínio não resolveu para nenhum IP."
  fi

  ui_confirm "O DNS pode não estar apontado corretamente. Instalar mesmo assim?"
}
