#!/usr/bin/env bash
# Step 2 — Upload agent ISO + create VMs via the single create-cluster Terraform state.
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
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
CLUSTER_TFVARS="${CLUSTER_TFVARS:-${CLUSTER_TF_DIR}/terraform.tfvars}"
PAR_FILE="${WORK_DIR}/iso-par-url.txt"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

iso_path=""
if [[ -f "${WORK_DIR}/agent-iso-path.txt" ]]; then
  iso_path="$(tr -d '[:space:]' <"${WORK_DIR}/agent-iso-path.txt")"
fi
if [[ -z "$iso_path" || ! -f "$iso_path" ]]; then
  iso_path="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"
fi
[[ -n "$iso_path" && -f "$iso_path" ]] || {
  echo "ERROR: no agent ISO under ${WORK_DIR}; run scripts/01_build_agent_iso.sh first" >&2
  exit 1
}

[[ -f "$CLUSTER_TFVARS" ]] || {
  echo "ERROR: missing ${CLUSTER_TFVARS}; copy option-2-agent-based/examples/terraform.tfvars.example" >&2
  exit 1
}

tmp="$(mktemp)"
awk -v iso="$iso_path" '
  BEGIN { done_inst=0; done_tags=0; done_iso=0 }
  /^[[:space:]]*create_openshift_instances[[:space:]]*=/ {
    print "create_openshift_instances = true"
    done_inst=1
    next
  }
  /^[[:space:]]*create_resource_attribution_tags[[:space:]]*=/ {
    print "create_resource_attribution_tags = false"
    done_tags=1
    next
  }
  /^[[:space:]]*agent_iso_file_path[[:space:]]*=/ {
    print "agent_iso_file_path = \"" iso "\""
    done_iso=1
    next
  }
  { print }
  END {
    if (!done_inst) print "create_openshift_instances = true"
    if (!done_tags) print "create_resource_attribution_tags = false"
    if (!done_iso) print "agent_iso_file_path = \"" iso "\""
  }
' "$CLUSTER_TFVARS" >"$tmp"
mv "$tmp" "$CLUSTER_TFVARS"

log "Applying create-cluster (ISO upload, PAR, custom images, instances)"
terraform -chdir="$CLUSTER_TF_DIR" init -input=false
terraform -chdir="$CLUSTER_TF_DIR" apply -input=false -auto-approve

par_url="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw agent_iso_par_url)"
printf '%s\n' "$par_url" >"$PAR_FILE"

cat <<EOF
============================================================
Step 2 complete (single Terraform state)
  ISO uploaded:     ${iso_path}
  PAR URL:          ${par_url}
  PAR file:         ${PAR_FILE}
  Terraform state:  ${CLUSTER_TF_DIR}

OpenShift agent install proceeds on the rendezvous node.
  kubeadmin: ${WORK_DIR}/auth/kubeadmin-password
  kubeconfig: ${WORK_DIR}/auth/kubeconfig

Monitor: scripts/03_monitor_install.sh (optional)
============================================================
EOF
