#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=lib/ui.sh
  source "$ROOT_DIR/lib/ui.sh"
  export VPS_INSTALLER_SOURCE_DIR="$ROOT_DIR"
  # shellcheck source=lib/appdef.sh
  source "$ROOT_DIR/lib/appdef.sh"
}

@test "appdef_list_slugs finds bundled catalog apps" {
  result="$(appdef_list_slugs | sort)"
  [[ "$result" == *"minio"* ]]
  [[ "$result" == *"rabbitmq"* ]]
}

@test "appdef_load populates manifest variables for minio" {
  appdef_load "minio"
  [ "$APP_LABEL" = "MinIO" ]
  [ "$APP_NEEDS_POSTGRES" = "false" ]
  [ -n "$APP_TESTED_TAGS" ]
}

@test "appdef_load fails for unknown slug" {
  run appdef_load "does-not-exist"
  [ "$status" -ne 0 ]
}

@test "appdef_image builds repo:tag" {
  appdef_load "minio"
  result="$(appdef_image "RELEASE.test")"
  [ "$result" = "minio/minio:RELEASE.test" ]
}

@test "appdef_split_semicolons splits into array" {
  appdef_split_semicolons "a:1;b:2;c:3"
  [ "${#__appdef_split_result[@]}" -eq 3 ]
  [ "${__appdef_split_result[0]}" = "a:1" ]
  [ "${__appdef_split_result[2]}" = "c:3" ]
}

@test "appdef_label_or_default returns manifest label" {
  result="$(appdef_label_or_default "rabbitmq" "fallback")"
  [ "$result" = "RabbitMQ" ]
}

@test "appdef_label_or_default falls back for unknown type" {
  result="$(appdef_label_or_default "does-not-exist" "fallback")"
  [ "$result" = "fallback" ]
}
