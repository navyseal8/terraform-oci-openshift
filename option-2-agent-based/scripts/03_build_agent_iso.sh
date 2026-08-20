#!/usr/bin/env bash
# Build agent ISO from prepared configs (no terraform commands).
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
SKIP_ISO_BUILD="${SKIP_ISO_BUILD:-0}"

mkdir -p "$WORK_DIR/openshift"
cd "$WORK_DIR"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

require_file() {
  local f="$1"
  [[ -f "$f" ]] || {
    echo "ERROR: missing ${WORK_DIR}/$f" >&2
    exit 1
  }
}

require_file "agent-config.yaml"
require_file "install-config.yaml"
require_file "openshift/oci-dynamic-custom-manifest.yaml"

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

  Re-generate install-config.yaml from your pipeline Terraform outputs, then rerun:
    ./option-2-agent-based/scripts/03_build_agent_iso.sh
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
ISO build complete
  ISO:              ${ISO_PATH}
  kubeadmin passwd: ${WORK_DIR}/auth/kubeadmin-password
  kubeconfig:       ${WORK_DIR}/auth/kubeconfig

Next: run your pipeline Terraform stage with:
  -var='create_openshift_instances=true'
  -var='agent_iso_file_path=${ISO_PATH}'
============================================================
EOF
