#!/usr/bin/env bash
# Step 1 — Infra-only apply (same state as step 2) + build agent ISO locally.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
CLUSTER_TFVARS="${CLUSTER_TFVARS:-${CLUSTER_TF_DIR}/terraform.tfvars}"
EXAMPLE="${REPO_ROOT}/option-2-agent-based/examples/terraform.tfvars.example"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if [[ ! -f "$CLUSTER_TFVARS" ]]; then
  log "Creating ${CLUSTER_TFVARS} from example"
  cp "$EXAMPLE" "$CLUSTER_TFVARS"
  echo "ERROR: edit terraform.tfvars then re-run" >&2
  exit 1
fi

log "Applying create-cluster infra only (tags, network, LB, DNS, IAM, ISO bucket)"
terraform -chdir="$CLUSTER_TF_DIR" init -input=false
terraform -chdir="$CLUSTER_TF_DIR" apply -input=false -auto-approve \
  -var="create_openshift_instances=false" \
  -var="agent_iso_file_path="

"${SCRIPT_DIR}/03_build_agent_iso.sh"
