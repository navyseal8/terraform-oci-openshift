#!/usr/bin/env bash
# Backward-compatible wrapper: build agent ISO only (no terraform commands).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "INFO: 01_prepare_and_build_iso.sh no longer runs terraform."
echo "INFO: Run pipeline Terraform phase A first, export configs into .work, then this script builds the ISO."
exec "${SCRIPT_DIR}/03_build_agent_iso.sh" "$@"
