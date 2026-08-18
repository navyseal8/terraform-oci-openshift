#!/usr/bin/env bash
# Deprecated wrapper — use 01_prepare_and_build_iso.sh + 02_apply_cluster_install.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "NOTE: use scripts/01_prepare_and_build_iso.sh and scripts/02_apply_cluster_install.sh" >&2
"${SCRIPT_DIR}/01_prepare_and_build_iso.sh"
"${SCRIPT_DIR}/02_apply_cluster_install.sh"
