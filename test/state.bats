#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=lib/ui.sh
  source "$ROOT_DIR/lib/ui.sh"
  TEST_HOME="$(mktemp -d)"
  export VPS_INSTALLER_HOME="$TEST_HOME"
  # shellcheck source=lib/state.sh
  source "$ROOT_DIR/lib/state.sh"
  state_init
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "state_set and state_get round-trip a simple value" {
  state_set MY_KEY "hello" "$STATE_DIR/test.env"
  result="$(state_get MY_KEY "$STATE_DIR/test.env")"
  [ "$result" = "hello" ]
}

@test "state_set and state_get preserve spaces and special characters" {
  state_set MY_KEY 'value with spaces & "quotes" and $dollar' "$STATE_DIR/test.env"
  result="$(state_get MY_KEY "$STATE_DIR/test.env")"
  [ "$result" = 'value with spaces & "quotes" and $dollar' ]
}

@test "state_set overwrites an existing key without duplicating it" {
  state_set MY_KEY "first" "$STATE_DIR/test.env"
  state_set MY_KEY "second" "$STATE_DIR/test.env"
  result="$(state_get MY_KEY "$STATE_DIR/test.env")"
  [ "$result" = "second" ]
  count="$(grep -c '^MY_KEY=' "$STATE_DIR/test.env")"
  [ "$count" -eq 1 ]
}

@test "state_get returns empty for missing key in existing file" {
  state_set OTHER_KEY "x" "$STATE_DIR/test.env"
  result="$(state_get MISSING_KEY "$STATE_DIR/test.env")"
  [ -z "$result" ]
}

@test "state_get fails for nonexistent file" {
  run state_get MY_KEY "$STATE_DIR/does-not-exist.env"
  [ "$status" -ne 0 ]
}

@test "state_register_app writes app file and registers in apps.tsv" {
  state_register_app "myapp" "myapp_stack" "custom" "example.com" "img:tag" "/tmp/stack.yml"
  [ -f "$APP_STATE_DIR/myapp.env" ]
  grep -q 'myapp' "$STATE_DIR/apps.tsv"
  result="$(state_get APP_DOMAIN "$APP_STATE_DIR/myapp.env")"
  [ "$result" = "example.com" ]
}

@test "state_remove_app removes app file and inventory entry" {
  state_register_app "myapp" "myapp_stack" "custom" "" "" ""
  state_remove_app "myapp"
  [ ! -f "$APP_STATE_DIR/myapp.env" ]
  run grep -q 'myapp' "$STATE_DIR/apps.tsv"
  [ "$status" -ne 0 ]
}
