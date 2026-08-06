#!/usr/bin/env bash
# Step 3 — Build agent ISO locally with openshift-install, upload to OCI, create PAR.
#
# Prerequisites: openshift-install (matching your OCP version), oci CLI, jq
# Inputs: Terraform outputs from phase A (or files already in WORK_DIR)
#
# Example:
#   export CLUSTER_NAME=ocidemo
#   export WORK_DIR=$PWD/option-3-agent-based/.work/$CLUSTER_NAME
#   export OCI_NAMESPACE=... OCI_BUCKET=... OCI_REGION=... OCI_COMPARTMENT_OCID=...
#   ./option-3-agent-based/scripts/03_create_agent_iso_par.sh
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

need_cmd jq
need_cmd oci

OPENSHIFT_INSTALL="${OPENSHIFT_INSTALL:-openshift-install}"
need_cmd "$OPENSHIFT_INSTALL"

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-3-agent-based/.work/${CLUSTER_NAME}}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
CLUSTER_STATE="${CLUSTER_STATE:-}" # optional: -state path if not default

OCI_NAMESPACE="${OCI_NAMESPACE:?}"
OCI_BUCKET="${OCI_BUCKET:?}"
OCI_REGION="${OCI_REGION:?}"
OCI_COMPARTMENT_OCID="${OCI_COMPARTMENT_OCID:?}"
OBJECT_NAME="${OBJECT_NAME:-${CLUSTER_NAME}-agent.iso}"
PAR_NAME="${PAR_NAME:-${CLUSTER_NAME}-agent-par}"
PAR_EXPIRE_DAYS="${PAR_EXPIRE_DAYS:-7}"

mkdir -p "$WORK_DIR/openshift"
cd "$WORK_DIR"

tf_out() {
  local name="$1"
  if [[ -n "$CLUSTER_STATE" ]]; then
    terraform -chdir="$CLUSTER_TF_DIR" output -state="$CLUSTER_STATE" -raw "$name"
  else
    terraform -chdir="$CLUSTER_TF_DIR" output -raw "$name"
  fi
}

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if [[ ! -f agent-config.yaml ]]; then
  log "Writing agent-config.yaml from terraform output"
  tf_out agent_config >agent-config.yaml
fi
if [[ ! -f install-config.yaml ]]; then
  log "Writing install-config.yaml from terraform output"
  tf_out install_config >install-config.yaml
fi
if [[ ! -f openshift/oci-dynamic-custom-manifest.yaml ]]; then
  log "Writing Oracle CCM/CSI manifest into openshift/"
  tf_out dynamic_custom_manifest >openshift/oci-dynamic-custom-manifest.yaml
fi

# openshift-install expects install-config.yaml / agent-config.yaml in the dir;
# it consumes and may remove them when creating the image — keep backups.
cp -f agent-config.yaml agent-config.yaml.bak
cp -f install-config.yaml install-config.yaml.bak

log "Running: ${OPENSHIFT_INSTALL} agent create image --dir ${WORK_DIR}"
"$OPENSHIFT_INSTALL" agent create image --dir "$WORK_DIR"

ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"
[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || {
  echo "ERROR: no agent ISO found under ${WORK_DIR}" >&2
  exit 1
}
log "ISO ready: ${ISO_PATH}"

[[ -f "$WORK_DIR/auth/kubeadmin-password" ]] || {
  echo "ERROR: auth/kubeadmin-password missing after image create" >&2
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
Step 3 complete (build locally + upload PAR)
  ISO:              ${ISO_PATH}
  PAR URL:          ${par_url}
  PAR file:         ${WORK_DIR}/iso-par-url.txt
  kubeadmin passwd: ${WORK_DIR}/auth/kubeadmin-password
  kubeconfig:       ${WORK_DIR}/auth/kubeconfig

Next: run scripts/04_apply_phase_b.sh (or apply phase-B tfvars).
============================================================
EOF
