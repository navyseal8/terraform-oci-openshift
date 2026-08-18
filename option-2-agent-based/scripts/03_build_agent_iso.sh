#!/usr/bin/env bash
# Step 3a — Build agent ISO locally with openshift-install (no OCI API calls).
set -euo pipefail

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

OPENSHIFT_INSTALL="${OPENSHIFT_INSTALL:-openshift-install}"
need_cmd "$OPENSHIFT_INSTALL"

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
CLUSTER_STATE="${CLUSTER_STATE:-}"
SKIP_ISO_BUILD="${SKIP_ISO_BUILD:-0}"

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

validate_ssh_key_in_install_config() {
  local key
  key="$(awk -F"'" '/^sshKey:/ {print $2; exit}' install-config.yaml)"
  if [[ -z "$key" ]]; then
    echo "ERROR: install-config.yaml has no sshKey (set public_ssh_key in terraform.tfvars)" >&2
    exit 1
  fi
  if [[ "$key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|ssh-dss)[[:space:]] ]]; then
    return 0
  fi
  cat >&2 <<EOF
ERROR: invalid public_ssh_key in install-config.yaml (sshKey field).

  openshift-install requires an OpenSSH *public* key, for example:
    ssh-ed25519 AAAA... you@host
    ssh-rsa AAAA... you@host

  Fix terraform-stacks/create-cluster/terraform.tfvars, run terraform apply, then:
    rm -f "${WORK_DIR}/install-config.yaml"
    terraform -chdir="${CLUSTER_TF_DIR}" output -raw install_config > "${WORK_DIR}/install-config.yaml"
EOF
  exit 1
}

validate_ssh_key_in_install_config

cp -f agent-config.yaml agent-config.yaml.bak
cp -f install-config.yaml install-config.yaml.bak

ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"

if [[ "$SKIP_ISO_BUILD" == "1" ]]; then
  [[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || {
    echo "ERROR: SKIP_ISO_BUILD=1 but no agent ISO found under ${WORK_DIR}" >&2
    exit 1
  }
  log "SKIP_ISO_BUILD=1 — using existing ISO: ${ISO_PATH}"
else
  log "Running: ${OPENSHIFT_INSTALL} agent create image --dir ${WORK_DIR}"
  if ! "$OPENSHIFT_INSTALL" agent create image --dir "$WORK_DIR"; then
    cat >&2 <<EOF
ERROR: openshift-install failed. See ${WORK_DIR}/.openshift_install.log

If agent*.iso already exists:
  export SKIP_ISO_BUILD=1
  ./option-2-agent-based/scripts/03_build_agent_iso.sh

For a clean rebuild:
  rm -f "${WORK_DIR}/.openshift_install_state.json" "${WORK_DIR}/.openshift_install.log"
  cp -f "${WORK_DIR}/agent-config.yaml.bak" "${WORK_DIR}/agent-config.yaml"
  cp -f "${WORK_DIR}/install-config.yaml.bak" "${WORK_DIR}/install-config.yaml"
  mkdir -p "${WORK_DIR}/openshift"
  terraform -chdir="${CLUSTER_TF_DIR}" output -raw dynamic_custom_manifest \\
    > "${WORK_DIR}/openshift/oci-dynamic-custom-manifest.yaml"
EOF
    exit 1
  fi
  ISO_PATH="$(find "$WORK_DIR" -maxdepth 1 -type f \( -name 'agent*.iso' -o -name '*.iso' \) | head -1)"
fi

[[ -n "$ISO_PATH" && -f "$ISO_PATH" ]] || {
  echo "ERROR: no agent ISO found under ${WORK_DIR}" >&2
  exit 1
}

log "ISO ready: ${ISO_PATH}"
echo "$ISO_PATH" >"${WORK_DIR}/agent-iso-path.txt"

if [[ "$SKIP_ISO_BUILD" != "1" ]]; then
  [[ -f "$WORK_DIR/auth/kubeadmin-password" ]] || {
    echo "ERROR: auth/kubeadmin-password missing after image create" >&2
    exit 1
  }
fi

cat <<EOF
============================================================
Step 3a complete (local ISO build)
  ISO:              ${ISO_PATH}
  kubeadmin passwd: ${WORK_DIR}/auth/kubeadmin-password
  kubeconfig:       ${WORK_DIR}/auth/kubeconfig

Next: upload ISO + create VMs with one Terraform apply (same state):
  ./option-2-agent-based/scripts/02_apply_cluster_install.sh
============================================================
EOF
