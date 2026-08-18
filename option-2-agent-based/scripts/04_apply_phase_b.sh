#!/usr/bin/env bash
# Deprecated — use 02_apply_cluster_install.sh (same single Terraform state).
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/02_apply_cluster_install.sh" "$@"
