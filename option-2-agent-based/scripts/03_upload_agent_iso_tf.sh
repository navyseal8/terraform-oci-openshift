#!/usr/bin/env bash
# Deprecated — PAR and upload are in create-cluster Terraform. Use 02_apply_cluster_install.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/02_apply_cluster_install.sh" "$@"
