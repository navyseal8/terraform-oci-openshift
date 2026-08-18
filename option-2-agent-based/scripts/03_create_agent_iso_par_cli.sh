#!/usr/bin/env bash
# Legacy step 3 — build ISO + upload/PAR via OCI CLI (not Terraform).
# Prefer: 03_build_agent_iso.sh + 03_upload_agent_iso_tf.sh
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

need_cmd jq
need_cmd oci

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"

OCI_NAMESPACE="${OCI_NAMESPACE:?}"
OCI_BUCKET="${OCI_BUCKET:?}"
OCI_REGION="${OCI_REGION:?}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:?}"
OBJECT_NAME="${OBJECT_NAME:-${CLUSTER_NAME}-agent.iso}"
PAR_NAME="${PAR_NAME:-${CLUSTER_NAME}-agent-par}"
PAR_EXPIRE_DAYS="${PAR_EXPIRE_DAYS:-7}"
SKIP_ISO_BUILD="${SKIP_ISO_BUILD:-0}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if [[ "$SKIP_ISO_BUILD" != "1" ]]; then
  "${SCRIPT_DIR}/03_build_agent_iso.sh"
fi

ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"
[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || {
  echo "ERROR: no agent ISO found under ${WORK_DIR}" >&2
  exit 1
}

log "Ensuring Object Storage bucket ${OCI_BUCKET}"
if ! oci os bucket get --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" --region "$OCI_REGION" >/dev/null 2>&1; then
  oci os bucket create \
    --namespace-name "$OCI_NAMESPACE" \
    --compartment-id "$OCI_COMPARTMENT_OCID" \
    --name "$OCI_BUCKET" \
    --region "$OCI_REGION" >/dev/null
fi

log "Uploading ${OBJECT_NAME}"
oci os object put \
  --namespace-name "$OCI_NAMESPACE" \
  --bucket-name "$OCI_BUCKET" \
  --name "$OBJECT_NAME" \
  --file "$ISO_PATH" \
  --region "$OCI_REGION" \
  --force >/dev/null

expire="$(date -u -d "+${PAR_EXPIRE_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -v+"${PAR_EXPIRE_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"

log "Creating PAR (expires ${expire})"
par_json="$(
  oci os preauth-request create \
    --namespace-name "$OCI_NAMESPACE" \
    --bucket-name "$OCI_BUCKET" \
    --name "$PAR_NAME" \
    --access-type ObjectRead \
    --time-expires "$expire" \
    --object-name "$OBJECT_NAME" \
    --region "$OCI_REGION"
)"

access_uri="$(jq -er '.data."access-uri"' <<<"$par_json")"
if [[ "$access_uri" == http* ]]; then
  par_url="$access_uri"
else
  par_url="https://objectstorage.${OCI_REGION}.oraclecloud.com${access_uri}"
fi

printf '%s\n' "$par_url" >"${WORK_DIR}/iso-par-url.txt"

cat <<EOF
============================================================
Step 3 complete (OCI CLI upload + PAR)
  ISO:              ${ISO_PATH}
  PAR URL:          ${par_url}
  PAR file:         ${WORK_DIR}/iso-par-url.txt

Next: run scripts/04_apply_phase_b.sh
============================================================
EOF
