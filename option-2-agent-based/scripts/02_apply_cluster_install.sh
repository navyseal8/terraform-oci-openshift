#!/usr/bin/env bash
# Deprecated: terraform apply is pipeline-owned, not script-owned.
set -euo pipefail

cat >&2 <<'EOF'
ERROR: 02_apply_cluster_install.sh is retired.

Run Terraform phase B in your pipeline instead, for example:
  terraform -chdir=terraform-stacks/create-cluster apply -input=false -auto-approve \
    -var='create_openshift_instances=true' \
    -var='create_resource_attribution_tags=false' \
    -var='agent_iso_file_path=/absolute/path/to/agent.x86_64.iso'

After apply:
  terraform -chdir=terraform-stacks/create-cluster output -raw agent_iso_par_url

Use scripts/03_monitor_install.sh to monitor cluster convergence.
EOF
exit 1
