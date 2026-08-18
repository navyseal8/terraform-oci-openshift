#!/usr/bin/env bash
# Step 3 — Build agent ISO locally, then upload bucket/object/PAR via Terraform.
#
# Split into:
#   03_build_agent_iso.sh       — openshift-install only (local)
#   03_upload_agent_iso_tf.sh   — OCI bucket, object, PAR (Terraform)
#
# Legacy OCI CLI upload: USE_OCI_CLI=1 ./option-2-agent-based/scripts/03_create_agent_iso_par.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${USE_OCI_CLI:-0}" == "1" ]]; then
  exec "${SCRIPT_DIR}/03_create_agent_iso_par_cli.sh" "$@"
fi

"${SCRIPT_DIR}/03_build_agent_iso.sh" "$@"
"${SCRIPT_DIR}/03_upload_agent_iso_tf.sh" "$@"
