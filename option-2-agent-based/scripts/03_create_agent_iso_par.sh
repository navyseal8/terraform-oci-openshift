#!/usr/bin/env bash
# Deprecated: pipeline owns terraform applies.
set -euo pipefail

cat >&2 <<'EOF'
ERROR: 03_create_agent_iso_par.sh is retired.

Use:
  1) scripts/03_build_agent_iso.sh to build ISO
  2) pipeline Terraform phase B with -var='agent_iso_file_path=/path/to/agent.x86_64.iso'
EOF
exit 1
