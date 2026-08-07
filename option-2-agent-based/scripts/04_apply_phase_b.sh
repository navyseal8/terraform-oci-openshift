#!/usr/bin/env bash
# Step 4 — Apply create-cluster phase B (instances from agent ISO PAR) and show kubeadmin.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
PHASE_B_TFVARS="${PHASE_B_TFVARS:-${CLUSTER_TF_DIR}/terraform.tfvars}"
EXAMPLE_B="${REPO_ROOT}/option-2-agent-based/examples/04-create-cluster-phase-b.tfvars.example"
PAR_FILE="${WORK_DIR}/iso-par-url.txt"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

[[ -f "$PAR_FILE" ]] || {
  echo "ERROR: missing ${PAR_FILE}; run scripts/03_create_agent_iso_par.sh first" >&2
  exit 1
}
par_url="$(tr -d '[:space:]' <"$PAR_FILE")"

if [[ ! -f "$PHASE_B_TFVARS" ]]; then
  log "No ${PHASE_B_TFVARS}; copying example — edit REPLACE_* values before re-running"
  cp "$EXAMPLE_B" "$PHASE_B_TFVARS"
  echo "ERROR: fill terraform.tfvars then re-run this script" >&2
  exit 1
fi

# Ensure phase-B flags and PAR URL are set (idempotent-ish replace of URI line)
tmp="$(mktemp)"
awk -v par="$par_url" '
  BEGIN { done_inst=0; done_uri=0 }
  /^[[:space:]]*create_openshift_instances[[:space:]]*=/ {
    print "create_openshift_instances = true"
    done_inst=1
    next
  }
  /^[[:space:]]*openshift_image_source_uri[[:space:]]*=/ {
    print "openshift_image_source_uri = \"" par "\""
    done_uri=1
    next
  }
  { print }
  END {
    if (!done_inst) print "create_openshift_instances = true"
    if (!done_uri) print "openshift_image_source_uri = \"" par "\""
  }
' "$PHASE_B_TFVARS" >"$tmp"
mv "$tmp" "$PHASE_B_TFVARS"

# Force Agent-based if someone left Assisted
if ! grep -q 'installation_method[[:space:]]*=[[:space:]]*"Agent-based"' "$PHASE_B_TFVARS"; then
  echo 'installation_method = "Agent-based"' >>"$PHASE_B_TFVARS"
fi

log "Applying create-cluster phase B with PAR"
terraform -chdir="$CLUSTER_TF_DIR" init -input=false >/dev/null
terraform -chdir="$CLUSTER_TF_DIR" apply -input=false -auto-approve

api_lb="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw open_shift_api_lb_addr 2>/dev/null || true)"
apps_lb="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw open_shift_apps_lb_addr 2>/dev/null || true)"
etc_hosts="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw etc_hosts_entry 2>/dev/null || true)"

kubeadmin_file="${WORK_DIR}/auth/kubeadmin-password"
kubeconfig_file="${WORK_DIR}/auth/kubeconfig"

cat <<EOF
============================================================
Step 4 — instances provisioning started / applied
  Agent ISO PAR was set in ${PHASE_B_TFVARS}
  API LB:  ${api_lb:-n/a}
  Apps LB: ${apps_lb:-n/a}

Kubeadmin credentials (from step 3 openshift-install):
  password file: ${kubeadmin_file}
  kubeconfig:    ${kubeconfig_file}

$(if [[ -f "$kubeadmin_file" ]]; then echo "  kubeadmin password: $(tr -d '[:space:]' <"$kubeadmin_file")"; else echo "  (password file missing — check WORK_DIR/auth)"; fi)

After bootstrap finishes (monitor rendezvous node if needed):
  export KUBECONFIG=${kubeconfig_file}
  oc get nodes
  oc get clusteroperators

Optional /etc/hosts:
${etc_hosts:-}
============================================================
EOF
