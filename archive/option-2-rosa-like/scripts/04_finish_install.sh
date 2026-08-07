#!/usr/bin/env bash
# Phase 4: Upload CCM/CSI manifests, assign host roles, start install, wait, fetch kubeconfig.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

workdir_init
STATE_FILE="${WORK_DIR}/assisted-state.json"
MANIFEST_OUT="${WORK_DIR}/dynamic_custom_manifest.yml"
KUBECONFIG_OUT="${WORK_DIR}/kubeconfig"
HOST_WAIT_TIMEOUT_SEC="${HOST_WAIT_TIMEOUT_SEC:-3600}"
INSTALL_WAIT_TIMEOUT_SEC="${INSTALL_WAIT_TIMEOUT_SEC:-7200}"

[[ -f "$STATE_FILE" && -f "$MANIFEST_OUT" ]] || {
  echo "ERROR: missing state or manifest; run earlier phases first" >&2
  exit 1
}

cluster_id="$(jq -er '.cluster_id' "$STATE_FILE")"
infra_env_id="$(jq -er '.infra_env_id' "$STATE_FILE")"
cp_count="$(jq -er '.control_plane_count' "$STATE_FILE")"
compute_count="$(jq -er '.compute_count' "$STATE_FILE")"
expected_hosts=$((cp_count + compute_count))

log "Uploading Oracle dynamic_custom_manifest to Assisted Installer"
manifest_b64="$(base64 -w 0 "$MANIFEST_OUT" 2>/dev/null || base64 <"$MANIFEST_OUT" | tr -d '\n')"
ai_curl POST "/clusters/${cluster_id}/manifests" -d "$(
  jq -n \
    --arg content "$manifest_b64" \
    '{file_name: "oci-dynamic-custom-manifest.yaml", folder: "manifests", content: $content}'
)" >/dev/null

log "Waiting for ${expected_hosts} hosts to register (timeout ${HOST_WAIT_TIMEOUT_SEC}s)"
deadline=$((SECONDS + HOST_WAIT_TIMEOUT_SEC))
while ((SECONDS < deadline)); do
  hosts_json="$(ai_curl GET "/infra-envs/${infra_env_id}/hosts")"
  host_count="$(jq 'length' <<<"$hosts_json")"
  log "Discovered hosts: ${host_count}/${expected_hosts}"
  if ((host_count >= expected_hosts)); then
    break
  fi
  sleep 30
done
hosts_json="$(ai_curl GET "/infra-envs/${infra_env_id}/hosts")"
host_count="$(jq 'length' <<<"$hosts_json")"
((host_count >= expected_hosts)) || {
  echo "ERROR: only ${host_count} hosts registered; expected ${expected_hosts}" >&2
  exit 1
}

log "Assigning host roles: first ${cp_count} -> master, remaining -> worker"
# Stable order by requested_hostname / id
mapfile -t host_ids < <(jq -r 'sort_by(.requested_hostname // .id) | .[].id' <<<"$hosts_json")
i=0
for hid in "${host_ids[@]}"; do
  if ((i < cp_count)); then
    role="master"
  else
    role="worker"
  fi
  log "Host ${hid} -> ${role}"
  ai_curl PATCH "/infra-envs/${infra_env_id}/hosts/${hid}" \
    -d "$(jq -n --arg role "$role" '{host_role: $role}')" >/dev/null
  i=$((i + 1))
done

log "Waiting until cluster status is ready"
deadline=$((SECONDS + HOST_WAIT_TIMEOUT_SEC))
while ((SECONDS < deadline)); do
  status="$(ai_curl GET "/clusters/${cluster_id}" | jq -r '.status')"
  log "Cluster status=${status}"
  case "$status" in
  ready | insufficient) ;;
  esac
  if [[ "$status" == "ready" ]]; then
    break
  fi
  sleep 30
done
status="$(ai_curl GET "/clusters/${cluster_id}" | jq -r '.status')"
[[ "$status" == "ready" ]] || {
  echo "ERROR: cluster not ready (status=${status})" >&2
  exit 1
}

log "Starting cluster installation"
ai_curl POST "/clusters/${cluster_id}/actions/install" >/dev/null || true

log "Waiting for install to finish (timeout ${INSTALL_WAIT_TIMEOUT_SEC}s)"
deadline=$((SECONDS + INSTALL_WAIT_TIMEOUT_SEC))
while ((SECONDS < deadline)); do
  cjson="$(ai_curl GET "/clusters/${cluster_id}")"
  status="$(jq -r '.status' <<<"$cjson")"
  status_info="$(jq -r '.status_info // empty' <<<"$cjson")"
  log "Install status=${status} info=${status_info}"
  if [[ "$status" == "installed" ]]; then
    break
  fi
  if [[ "$status" == "error" || "$status" == "cancelled" ]]; then
    echo "ERROR: installation failed with status=${status}" >&2
    exit 1
  fi
  sleep 60
done
status="$(ai_curl GET "/clusters/${cluster_id}" | jq -r '.status')"
[[ "$status" == "installed" ]] || {
  echo "ERROR: install did not complete (status=${status})" >&2
  exit 1
}

log "Downloading kubeconfig to ${KUBECONFIG_OUT}"
refresh_api_token
curl -sS --fail \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Accept: application/octet-stream" \
  -o "$KUBECONFIG_OUT" \
  "${AI_API_BASE}/clusters/${cluster_id}/downloads/credentials?file_name=kubeconfig"

jq --arg kube "$KUBECONFIG_OUT" '. + {kubeconfig_path: $kube, status: "installed"}' \
  "$STATE_FILE" >"${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

api_lb="$(jq -r '.open_shift_api_lb_addr.value // empty' "${WORK_DIR}/oci-infra-outputs.json" 2>/dev/null || true)"
apps_lb="$(jq -r '.open_shift_apps_lb_addr.value // empty' "${WORK_DIR}/oci-infra-outputs.json" 2>/dev/null || true)"
cluster_name="$(jq -er '.cluster_name' "$STATE_FILE")"
base_domain="$(jq -er '.base_domain' "$STATE_FILE")"

cat <<EOF
============================================================
OpenShift install complete (Option 2 ROSA-like facade)
  cluster:  ${cluster_name}.${base_domain}
  kubeconfig: ${KUBECONFIG_OUT}
  api LB IP:  ${api_lb:-n/a}
  apps LB IP: ${apps_lb:-n/a}

  export KUBECONFIG=${KUBECONFIG_OUT}
  oc get nodes
============================================================
EOF
