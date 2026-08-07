#!/usr/bin/env bash
# Phase 2: Download discovery ISO and upload to OCI Object Storage; create PAR URL.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need_cmd oci

workdir_init
STATE_FILE="${WORK_DIR}/assisted-state.json"
[[ -f "$STATE_FILE" ]] || {
  echo "ERROR: missing ${STATE_FILE}; run 01_register_assisted.sh first" >&2
  exit 1
}

infra_env_id="$(jq -er '.infra_env_id' "$STATE_FILE")"
CLUSTER_NAME="$(jq -er '.cluster_name' "$STATE_FILE")"

OCI_NAMESPACE="${OCI_NAMESPACE:?}"
OCI_BUCKET="${OCI_BUCKET:?}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:?}"
OCI_REGION="${OCI_REGION:?}"
OBJECT_NAME="${OBJECT_NAME:-${CLUSTER_NAME}-discovery.iso}"
PAR_NAME="${PAR_NAME:-${CLUSTER_NAME}-discovery-par}"
PAR_EXPIRE_DAYS="${PAR_EXPIRE_DAYS:-7}"

ISO_PATH="${WORK_DIR}/${OBJECT_NAME}"
PAR_FILE="${WORK_DIR}/iso-par-url.txt"

if [[ -f "$PAR_FILE" && -s "$PAR_FILE" ]]; then
  log "Reusing existing PAR URL at ${PAR_FILE}"
  cat "$PAR_FILE"
  exit 0
fi

log "Fetching discovery ISO download URL for infra_env=${infra_env_id}"
# Wait until image is ready
for _ in $(seq 1 60); do
  url_json="$(ai_curl GET "/infra-envs/${infra_env_id}/downloads/image-url" || true)"
  iso_url="$(jq -r '.url // empty' <<<"$url_json" 2>/dev/null || true)"
  if [[ -n "$iso_url" && "$iso_url" != "null" ]]; then
    break
  fi
  log "ISO not ready yet; sleeping 10s"
  sleep 10
done
[[ -n "${iso_url:-}" ]] || {
  echo "ERROR: timed out waiting for discovery ISO URL" >&2
  exit 1
}

log "Downloading discovery ISO to ${ISO_PATH}"
curl -sS --fail -L -o "$ISO_PATH" "$iso_url"

log "Ensuring Object Storage bucket ${OCI_BUCKET} exists in namespace ${OCI_NAMESPACE}"
if ! oci os bucket get --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" >/dev/null 2>&1; then
  oci os bucket create \
    --namespace-name "$OCI_NAMESPACE" \
    --compartment-id "$OCI_COMPARTMENT_OCID" \
    --name "$OCI_BUCKET" \
    --region "$OCI_REGION" >/dev/null
fi

log "Uploading ISO object ${OBJECT_NAME}"
oci os object put \
  --namespace-name "$OCI_NAMESPACE" \
  --bucket-name "$OCI_BUCKET" \
  --name "$OBJECT_NAME" \
  --file "$ISO_PATH" \
  --region "$OCI_REGION" \
  --force >/dev/null

expire="$(date -u -d "+${PAR_EXPIRE_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
  date -u -v+"${PAR_EXPIRE_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"

log "Creating Pre-Authenticated Request (expires ${expire})"
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

# access-uri is relative; build full URL
access_uri="$(jq -er '.data."access-uri"' <<<"$par_json")"
if [[ "$access_uri" == http* ]]; then
  par_url="$access_uri"
else
  par_url="https://objectstorage.${OCI_REGION}.oraclecloud.com${access_uri}"
fi

printf '%s\n' "$par_url" >"$PAR_FILE"
jq --arg par "$par_url" --arg object "$OBJECT_NAME" \
  '. + {iso_par_url: $par, iso_object_name: $object}' \
  "$STATE_FILE" >"${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

log "PAR URL written to ${PAR_FILE}"
echo "$par_url"
