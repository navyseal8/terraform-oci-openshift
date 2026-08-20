#!/usr/bin/env bash
# Disconnected only — copy agent rootfs to the webserver httpd docroot.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
SSH_USER="${SSH_USER:-opc}"
WEBSERVER_DOCROOT="${WEBSERVER_DOCROOT:-/var/www/html}"
WEBSERVER_PRIVATE_IP="${WEBSERVER_PRIVATE_IP:-}"
# SSH target for upload. Use public IP when running outside the VCN; private IP from a bastion/jump host.
WEBSERVER_SSH_HOST="${WEBSERVER_SSH_HOST:-${WEBSERVER_PUBLIC_IP:-}}"
BOOT_ARTIFACTS_BASE_URL="${BOOT_ARTIFACTS_BASE_URL:-}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

rootfs_file=""
if [[ -d "${WORK_DIR}/boot-artifacts" ]]; then
  rootfs_file="$(find "${WORK_DIR}/boot-artifacts" -name 'agent.x86_64-rootfs.img' | head -1)"
fi
[[ -z "$rootfs_file" ]] && rootfs_file="$(find "$WORK_DIR" -name 'agent.x86_64-rootfs.img' | head -1)"
[[ -n "$rootfs_file" && -f "$rootfs_file" ]] || {
  echo "ERROR: agent rootfs not found under ${WORK_DIR} (expected boot-artifacts/agent.x86_64-rootfs.img)" >&2
  exit 1
}

[[ -n "$WEBSERVER_SSH_HOST" ]] || {
  cat >&2 <<'EOF'
ERROR: set WEBSERVER_SSH_HOST (or WEBSERVER_PUBLIC_IP) for scp/ssh upload.

From outside the VCN, use the webserver public IP:
  export WEBSERVER_SSH_HOST="$(terraform -chdir=terraform-stacks/create-cluster output -raw webserver_public_ip)"

From inside the VCN (bastion), you can use the private IP:
  export WEBSERVER_SSH_HOST="$WEBSERVER_PRIVATE_IP"
EOF
  exit 1
}

[[ -n "$WEBSERVER_PRIVATE_IP" ]] || WEBSERVER_PRIVATE_IP="$WEBSERVER_SSH_HOST"

log "Uploading ${rootfs_file} to ${SSH_USER}@${WEBSERVER_SSH_HOST}:${WEBSERVER_DOCROOT}/"
scp "$rootfs_file" "${SSH_USER}@${WEBSERVER_SSH_HOST}:/tmp/agent.x86_64-rootfs.img"
ssh "${SSH_USER}@${WEBSERVER_SSH_HOST}" "sudo mv /tmp/agent.x86_64-rootfs.img ${WEBSERVER_DOCROOT}/ && sudo chmod a+r ${WEBSERVER_DOCROOT}/agent.x86_64-rootfs.img"

rootfs_url="${BOOT_ARTIFACTS_BASE_URL%/}/agent.x86_64-rootfs.img"
if [[ -z "$BOOT_ARTIFACTS_BASE_URL" ]]; then
  rootfs_url="http://${WEBSERVER_PRIVATE_IP}/agent.x86_64-rootfs.img"
fi

cat <<EOF
============================================================
Rootfs uploaded for disconnected install
  URL: ${rootfs_url}

Next: run your pipeline Terraform phase B with agent_iso_file_path set.
============================================================
EOF
