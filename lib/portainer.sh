#!/usr/bin/env bash

PORTAINER_JWT=""
PORTAINER_ENDPOINT_ID=""
PORTAINER_SWARM_ID=""

portainer_require_config() {
  state_init
  state_source "$STATE_DIR/portainer.env" || fail "Credenciais do Portainer nao configuradas. Instale a base primeiro."
  [[ -n "${PORTAINER_API_URL:-${PORTAINER_URL:-}}" && -n "${PORTAINER_USER:-}" && -n "${PORTAINER_PASSWORD:-}" ]] \
    || fail "Credenciais do Portainer incompletas."
}

portainer_api_base() {
  printf '%s' "${PORTAINER_API_URL:-$PORTAINER_URL}"
}

portainer_login() {
  portainer_require_config
  local base response
  base="$(portainer_api_base)"
  response="$(curl -k -fsSL -X POST "$base/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$PORTAINER_USER\",\"password\":\"$PORTAINER_PASSWORD\"}")"
  PORTAINER_JWT="$(printf '%s' "$response" | jq -r '.jwt // empty')"
  [[ -n "$PORTAINER_JWT" ]] || fail "Nao foi possivel autenticar no Portainer."
  printf '%s' "$PORTAINER_JWT"
}

portainer_endpoint_id() {
  [[ -n "$PORTAINER_JWT" ]] || portainer_login >/dev/null
  local base response
  base="$(portainer_api_base)"
  response="$(curl -k -fsSL "$base/api/endpoints" -H "Authorization: Bearer $PORTAINER_JWT")"
  PORTAINER_ENDPOINT_ID="$(printf '%s' "$response" | jq -r 'map(select(.Type == 2 or .Type == 1)) | .[0].Id // empty')"
  [[ -n "$PORTAINER_ENDPOINT_ID" ]] || fail "Endpoint do Portainer nao encontrado."
  printf '%s' "$PORTAINER_ENDPOINT_ID"
}

portainer_swarm_id() {
  [[ -n "$PORTAINER_ENDPOINT_ID" ]] || portainer_endpoint_id >/dev/null
  [[ -n "$PORTAINER_JWT" ]] || portainer_login >/dev/null
  local base response
  base="$(portainer_api_base)"
  response="$(curl -k -fsSL "$base/api/endpoints/$PORTAINER_ENDPOINT_ID/docker/swarm" \
    -H "Authorization: Bearer $PORTAINER_JWT")"
  PORTAINER_SWARM_ID="$(printf '%s' "$response" | jq -r '.ID // empty')"
  [[ -n "$PORTAINER_SWARM_ID" ]] || fail "Swarm ID nao encontrado pelo Portainer."
  printf '%s' "$PORTAINER_SWARM_ID"
}

portainer_stack_id() {
  local stack_name="$1"
  [[ -n "$PORTAINER_ENDPOINT_ID" ]] || portainer_endpoint_id >/dev/null
  [[ -n "$PORTAINER_JWT" ]] || portainer_login >/dev/null
  local base
  base="$(portainer_api_base)"
  curl -k -fsSL "$base/api/stacks" -H "Authorization: Bearer $PORTAINER_JWT" \
    | jq -r --arg name "$stack_name" '.[] | select(.Name == $name) | .Id' | head -n 1
}

portainer_stack_exists() {
  local stack_name="$1"
  [[ -n "$(portainer_stack_id "$stack_name")" ]]
}

portainer_deploy_stack() {
  local stack_name="$1"
  local stack_file="$2"
  stack_validate_file "$stack_file"

  [[ -n "$PORTAINER_JWT" ]] || portainer_login >/dev/null
  [[ -n "$PORTAINER_ENDPOINT_ID" ]] || portainer_endpoint_id >/dev/null
  [[ -n "$PORTAINER_SWARM_ID" ]] || portainer_swarm_id >/dev/null

  if portainer_stack_exists "$stack_name"; then
    fail "A stack '$stack_name' ja existe. Remova antes de instalar novamente."
  fi

  local base
  base="$(portainer_api_base)"
  ui_info "Enviando stack '$stack_name' para o Portainer..."
  curl -k -fsSL -X POST "$base/api/stacks/create/swarm/file?endpointId=$PORTAINER_ENDPOINT_ID" \
    -H "Authorization: Bearer $PORTAINER_JWT" \
    -F "Name=$stack_name" \
    -F "SwarmID=$PORTAINER_SWARM_ID" \
    -F "file=@$stack_file" >/dev/null
  ui_success "Stack criada: $stack_name"
  system_wait_stack "$stack_name" 180 || true
}

portainer_remove_stack() {
  local stack_name="$1"
  local stack_id
  stack_id="$(portainer_stack_id "$stack_name")"
  [[ -n "$stack_id" ]] || fail "Stack nao encontrada no Portainer: $stack_name"

  local base
  base="$(portainer_api_base)"
  curl -k -fsSL -X DELETE "$base/api/stacks/$stack_id?endpointId=$PORTAINER_ENDPOINT_ID" \
    -H "Authorization: Bearer $PORTAINER_JWT" >/dev/null
}
