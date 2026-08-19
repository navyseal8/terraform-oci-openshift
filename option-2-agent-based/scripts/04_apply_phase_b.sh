#!/usr/bin/env bash
# Deprecated: terraform apply is pipeline-owned, not script-owned.
set -euo pipefail

cat >&2 <<'EOF'
ERROR: 04_apply_phase_b.sh is retired.

Run Terraform phase B in your pipeline:
  terraform -chdir=terraform-stacks/create-cluster apply -input=false -auto-approve \
    -var='create_openshift_instances=true' \
    -var='create_resource_attribution_tags=false' \
    -var='agent_iso_file_path=/absolute/path/to/agent.x86_64.iso'
EOF
exit 1
