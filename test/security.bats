#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=lib/ui.sh
  source "$ROOT_DIR/lib/ui.sh"
  # shellcheck source=lib/security.sh
  source "$ROOT_DIR/lib/security.sh"
}

@test "security_list_public_ports reports public listeners" {
  ss() {
    printf '%s\n' 'tcp LISTEN 0 4096 0.0.0.0:9000 0.0.0.0:* users:((docker-proxy,pid=1))'
  }

  run security_list_public_ports

  [ "$status" -eq 0 ]
  [ "$output" = "9000/tcp docker-proxy,pid=1" ]
}

@test "security_list_public_ports reports wildcard listeners" {
  ss() {
    printf '%s\n' 'tcp LISTEN 0 4096 *:443 *:* users:((traefik,pid=2))'
  }

  run security_list_public_ports

  [ "$status" -eq 0 ]
  [ "$output" = "443/tcp traefik,pid=2" ]
}
@test "security_list_public_ports tolerates ss failure" {
  ss() {
    return 1
  }

  run security_list_public_ports

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "security_ssh_setting tolerates sshd failure" {
  sshd() {
    return 1
  }

  run security_ssh_setting permitrootlogin

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
