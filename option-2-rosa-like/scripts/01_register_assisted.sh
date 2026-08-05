#!/usr/bin/env bash
# Phase 1: Register Assisted Installer cluster + infra-env (OCI external platform).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

workdir_init

CLUSTER_NAME="${CLUSTER_NAME:?}"
BASE_DOMAIN="${BASE_DOMAIN:?}"
OPENSHIFT_VERSION="${OPENSHIFT_VERSION:?}"
PULL_SECRET="${PULL_SECRET:?}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:?}"
CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"
COMPUTE_COUNT="${COMPUTE_COUNT:-2}"
MACHINE_CIDR="${MACHINE_CIDR:-10.0.0.0/16}"
CLUSTER_NETWORK_CIDR="${CLUSTER_NETWORK_CIDR:-10.128.0.0/14}"
SERVICE_NETWORK_CIDR="${SERVICE_NETWORK_CIDR:-172.30.0.0/16}"
CLUSTER_NETWORK_HOST_PREFIX="${CLUSTER_NETWORK_HOST_PREFIX:-23}"

STATE_FILE="${WORK_DIR}/assisted-state.json"

if [[ -f "$STATE_FILE" ]]; then
  existing_id="$(jq -r '.cluster_id // empty' "$STATE_FILE")"
  if [[ -n "$existing_id" ]]; then
    log "Reusing existing Assisted cluster_id=${existing_id}"
    echo "$existing_id"
    exit 0
  fi
fi

log "Registering Assisted Installer cluster name=${CLUSTER_NAME} platform=oci"

payload="$(jq -n \
  --arg name "$CLUSTER_NAME" \
  --arg domain "$BASE_DOMAIN" \
  --arg version "$OPENSHIFT_VERSION" \
  --arg pull "$PULL_SECRET" \
  --arg ssh "$SSH_PUBLIC_KEY" \
  --argjson cp "$CONTROL_PLANE_COUNT" \
  --arg machine "$MACHINE_CIDR" \
  --arg cluster_net "$CLUSTER_NETWORK_CIDR" \
  --arg service_net "$SERVICE_NETWORK_CIDR" \
  --argjson host_prefix "$CLUSTER_NETWORK_HOST_PREFIX" \
  '{
     name: $name,
     base_dns_domain: $domain,
     openshift_version: $version,
     pull_secret: $pull,
     ssh_public_key: $ssh,
     control_plane_count: $cp,
     user_managed_networking: true,
     vip_dhcp_allocation: false,
     cluster_network_cidr: $cluster_net,
     cluster_network_host_prefix: $host_prefix,
     service_network_cidr: $service_net,
     machine_networks: [{ cidr: $machine }],
     platform: {
       type: "external",
       external: {
         platform_name: "oci",
         cloud_controller_manager: "External"
       }
     }
   }')"

cluster_json="$(ai_curl POST /clusters -d "$payload")"
cluster_id="$(jq -er '.id' <<<"$cluster_json")"
log "Created cluster_id=${cluster_id}"

infra_payload="$(jq -n \
  --arg name "${CLUSTER_NAME}-infra-env" \
  --arg cluster_id "$cluster_id" \
  --arg version "$OPENSHIFT_VERSION" \
  --arg pull "$PULL_SECRET" \
  --arg ssh "$SSH_PUBLIC_KEY" \
  '{
     name: $name,
     cluster_id: $cluster_id,
     openshift_version: $version,
     pull_secret: $pull,
     ssh_authorized_key: $ssh,
     image_type: "minimal-iso"
   }')"

infra_json="$(ai_curl POST /infra-envs -d "$infra_payload")"
infra_env_id="$(jq -er '.id' <<<"$infra_json")"
log "Created infra_env_id=${infra_env_id}"

jq -n \
  --arg cluster_id "$cluster_id" \
  --arg infra_env_id "$infra_env_id" \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg base_domain "$BASE_DOMAIN" \
  --argjson compute_count "$COMPUTE_COUNT" \
  --argjson control_plane_count "$CONTROL_PLANE_COUNT" \
  '{
     cluster_id: $cluster_id,
     infra_env_id: $infra_env_id,
     cluster_name: $cluster_name,
     base_domain: $base_domain,
     control_plane_count: $control_plane_count,
     compute_count: $compute_count
   }' >"$STATE_FILE"

echo "$cluster_id"
