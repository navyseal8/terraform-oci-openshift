#!/usr/bin/env bash
# Disconnected only — copy agent rootfs to the webserver httpd docroot.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/option-2-agent-based/.work/${CLUSTER_NAME}}"
CLUSTER_TF_DIR="${CLUSTER_TF_DIR:-${REPO_ROOT}/terraform-stacks/create-cluster}"
SSH_USER="${SSH_USER:-opc}"
WEBSERVER_DOCROOT="${WEBSERVER_DOCROOT:-/var/www/html}"

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

webserver_ip="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw webserver_private_ip)"
[[ -n "$webserver_ip" ]] || {
  echo "ERROR: webserver_private_ip output missing — was disconnected infra apply run?" >&2
  exit 1
}

log "Uploading ${rootfs_file} to ${SSH_USER}@${webserver_ip}:${WEBSERVER_DOCROOT}/"
scp "$rootfs_file" "${SSH_USER}@${webserver_ip}:/tmp/agent.x86_64-rootfs.img"
ssh "${SSH_USER}@${webserver_ip}" "sudo mv /tmp/agent.x86_64-rootfs.img ${WEBSERVER_DOCROOT}/ && sudo chmod a+r ${WEBSERVER_DOCROOT}/agent.x86_64-rootfs.img"

base_url="$(terraform -chdir="$CLUSTER_TF_DIR" output -raw boot_artifacts_base_url)"
cat <<EOF
============================================================
Rootfs uploaded for disconnected install
  URL: ${base_url}/agent.x86_64-rootfs.img

Next: ./option-2-agent-based/scripts/02_apply_cluster_install.sh
============================================================
EOF
