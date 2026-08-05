#!/usr/bin/env bash
# Shared helpers for Option 2 Assisted Installer + OCI orchestration.
set -euo pipefail

AI_API_BASE="${AI_API_BASE:-https://api.openshift.com/api/assisted-install/v2}"
SSO_TOKEN_URL="${SSO_TOKEN_URL:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd jq
need_cmd base64

workdir_init() {
  local dir="${WORK_DIR:?WORK_DIR is required}"
  mkdir -p "$dir"
}

refresh_api_token() {
  local offline="${RH_OFFLINE_TOKEN:?RH_OFFLINE_TOKEN is required}"
  API_TOKEN="$(
    curl -sS --fail -X POST "$SSO_TOKEN_URL" \
      -d grant_type=refresh_token \
      -d client_id=cloud-services \
      -d refresh_token="$offline" |
      jq -er '.access_token'
  )"
  export API_TOKEN
}

ai_curl() {
  # Usage: ai_curl METHOD PATH [curl args...]
  local method="$1"
  local path="$2"
  shift 2
  refresh_api_token
  curl -sS --fail -X "$method" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$@" \
    "${AI_API_BASE}${path}"
}

write_json() {
  local file="$1"
  cat >"$file"
}

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}
