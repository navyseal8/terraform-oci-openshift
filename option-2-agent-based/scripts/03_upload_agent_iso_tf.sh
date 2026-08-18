#!/usr/bin/env bash
# Step 3b — Upload agent ISO to OCI Object Storage and create PAR via Terraform.
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

need_cmd terraform

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
ISO_TF_DIR="${ISO_TF_DIR:-${REPO_ROOT}/option-2-agent-based/terraform/agent-iso-storage}"
ISO_TFVARS="${ISO_TFVARS:-${ISO_TF_DIR}/terraform.tfvars}"
ISO_TFVARS_EXAMPLE="${REPO_ROOT}/option-2-agent-based/terraform/agent-iso-storage/terraform.tfvars.example"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

iso_path=""
if [[ -f "${WORK_DIR}/agent-iso-path.txt" ]]; then
  iso_path="$(tr -d '[:space:]' <"${WORK_DIR}/agent-iso-path.txt")"
fi
if [[ -z "$iso_path" || ! -f "$iso_path" ]]; then
  iso_path="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"
fi
[[ -n "$iso_path" && -f "$iso_path" ]] || {
  echo "ERROR: no agent ISO under ${WORK_DIR}; run scripts/03_build_agent_iso.sh first" >&2
  exit 1
}

if [[ ! -f "$ISO_TFVARS" ]]; then
  log "Creating ${ISO_TFVARS} from example — edit compartment/region/bucket if needed"
  cp "$ISO_TFVARS_EXAMPLE" "$ISO_TFVARS"
fi

# Keep agent_iso_file_path in sync with the built ISO.
tmp="$(mktemp)"
awk -v iso="$iso_path" -v cluster="$CLUSTER_NAME" '
  /^[[:space:]]*agent_iso_file_path[[:space:]]*=/ {
    print "agent_iso_file_path = \"" iso "\""
    next
  }
  /^[[:space:]]*cluster_name[[:space:]]*=/ {
    print "cluster_name = \"" cluster "\""
    next
  }
  { print }
' "$ISO_TFVARS" >"$tmp"
mv "$tmp" "$ISO_TFVARS"

log "Applying agent-iso-storage Terraform (bucket, object upload, PAR)"
terraform -chdir="$ISO_TF_DIR" init -input=false
terraform -chdir="$ISO_TF_DIR" apply -input=false -auto-approve

par_url="$(terraform -chdir="$ISO_TF_DIR" output -raw agent_iso_par_url)"
printf '%s\n' "$par_url" >"${WORK_DIR}/iso-par-url.txt"

cat <<EOF
============================================================
Step 3b complete (Terraform Object Storage)
  ISO file:    ${iso_path}
  PAR URL:     ${par_url}
  PAR file:    ${WORK_DIR}/iso-par-url.txt
  TF state:    ${ISO_TF_DIR}

Next: run scripts/04_apply_phase_b.sh
============================================================
EOF
