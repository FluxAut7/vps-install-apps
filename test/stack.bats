#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=lib/ui.sh
  source "$ROOT_DIR/lib/ui.sh"
  # shellcheck source=lib/stack.sh
  source "$ROOT_DIR/lib/stack.sh"
  TMP_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "stack_sed_escape escapes slashes, ampersands and pipes" {
  result="$(stack_sed_escape 'a/b&c|d')"
  [ "$result" = 'a\/b\&c\|d' ]
}

@test "stack_render substitutes placeholders including special characters" {
  template="$TMP_DIR/template.yml"
  output="$TMP_DIR/output.yml"
  cat > "$template" <<'EOF'
services:
  app:
    password: __PASSWORD__
    path: __PATH__
EOF

  stack_render "$template" "$output" PASSWORD 'a/b&c' PATH '/usr/local'

  grep -q 'password: a/b&c' "$output"
  grep -q 'path: /usr/local' "$output"
}

@test "stack_render fails when template is missing" {
  run stack_render "$TMP_DIR/does-not-exist.yml" "$TMP_DIR/out.yml" KEY value
  [ "$status" -ne 0 ]
}

@test "stack_validate_file fails on empty file" {
  touch "$TMP_DIR/empty.yml"
  run stack_validate_file "$TMP_DIR/empty.yml"
  [ "$status" -ne 0 ]
}

@test "stack_validate_file fails when services section is missing" {
  printf 'foo: bar\n' > "$TMP_DIR/invalid.yml"
  run stack_validate_file "$TMP_DIR/invalid.yml"
  [ "$status" -ne 0 ]
}

@test "stack_validate_file passes with services section" {
  printf 'services:\n  app:\n    image: alpine\n' > "$TMP_DIR/valid.yml"
  run stack_validate_file "$TMP_DIR/valid.yml"
  [ "$status" -eq 0 ]
}

@test "stack_path builds path under STACKS_DIR" {
  STACKS_DIR="/opt/vps-installer/stacks"
  result="$(stack_path myapp)"
  [ "$result" = "/opt/vps-installer/stacks/myapp.yml" ]
}
