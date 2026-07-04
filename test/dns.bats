#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=lib/ui.sh
  source "$ROOT_DIR/lib/ui.sh"
  # shellcheck source=lib/dns.sh
  source "$ROOT_DIR/lib/dns.sh"
}

@test "dns_check_domain succeeds when resolved ip matches public ip" {
  dns_public_ip() { printf '203.0.113.10'; }
  dns_resolve() { printf '203.0.113.10\n'; }
  run dns_check_domain "example.com"
  [ "$status" -eq 0 ]
}

@test "dns_check_domain fails when resolved ip does not match" {
  dns_public_ip() { printf '203.0.113.10'; }
  dns_resolve() { printf '198.51.100.20\n'; }
  run dns_check_domain "example.com"
  [ "$status" -ne 0 ]
}

@test "dns_check_domain fails when domain does not resolve" {
  dns_public_ip() { printf '203.0.113.10'; }
  dns_resolve() { printf ''; }
  run dns_check_domain "example.com"
  [ "$status" -ne 0 ]
}

@test "dns_check_domain matches one of multiple resolved ips" {
  dns_public_ip() { printf '203.0.113.10'; }
  dns_resolve() { printf '198.51.100.20\n203.0.113.10\n'; }
  run dns_check_domain "example.com"
  [ "$status" -eq 0 ]
}

@test "dns_is_cloudflare_ip detects known Cloudflare ranges" {
  run dns_is_cloudflare_ip "104.16.5.5"
  [ "$status" -eq 0 ]
}

@test "dns_is_cloudflare_ip rejects unrelated ip" {
  run dns_is_cloudflare_ip "8.8.8.8"
  [ "$status" -ne 0 ]
}
