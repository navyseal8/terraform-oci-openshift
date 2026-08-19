#!/usr/bin/env bash
# Verify OCI Autoscaler operator after cluster install (step 3).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"

if [[ -f "${WORK_DIR}/auth/kubeconfig" ]]; then
  export KUBECONFIG="${WORK_DIR}/auth/kubeconfig"
elif [[ -z "${KUBECONFIG:-}" ]]; then
  echo "ERROR: set KUBECONFIG or ensure ${WORK_DIR}/auth/kubeconfig exists" >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}
need_cmd oc

echo "=== Cluster version ==="
oc get clusterversion version -o wide 2>/dev/null || true

echo
echo "=== Autoscaler namespace ==="
oc get pods -n oci-openshift-autoscaling-operator 2>/dev/null || {
  echo "Namespace oci-openshift-autoscaling-operator not found."
  echo "Was use_autoscaling_operator=true in terraform.tfvars?"
  exit 1
}

echo
echo "=== OCIClusterAutoscaler CR ==="
oc get ociclusterautoscaler -n oci-openshift-autoscaling-operator 2>/dev/null || true

echo
echo "=== Machines / nodes ==="
oc get machines -A 2>/dev/null | head -20 || true
oc get nodes 2>/dev/null || true

cat <<'EOF'

Expected when healthy:
  - capoci-controller-manager pod Running in oci-openshift-autoscaling-operator
  - oci-capi-operator-activate-after-install job Completed
  - ociclusterautoscaler CR present
  - worker nodes scale between autoscaler_node_minimum_count and autoscaler_node_maximum_count

EOF
