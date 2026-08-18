#!/usr/bin/env bash
# Optional — quick checks after step 2 (cluster VMs booting / agent install).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"

if [[ -f "${WORK_DIR}/auth/kubeconfig" ]]; then
  export KUBECONFIG="${WORK_DIR}/auth/kubeconfig"
  oc get nodes 2>/dev/null || true
  oc get clusteroperators 2>/dev/null || true
fi

terraform -chdir="$CLUSTER_TF_DIR" output etc_hosts_entry 2>/dev/null || true

if [[ -f "${WORK_DIR}/auth/kubeadmin-password" ]]; then
  echo "kubeadmin password: $(tr -d '[:space:]' <"${WORK_DIR}/auth/kubeadmin-password")"
fi
