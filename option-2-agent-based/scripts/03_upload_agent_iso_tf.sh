#!/usr/bin/env bash
# Deprecated: pipeline owns terraform apply.
set -euo pipefail

cat >&2 <<'EOF'
ERROR: 03_upload_agent_iso_tf.sh is retired.

Run Terraform phase B in your pipeline with:
  -var='create_openshift_instances=true'
  -var='create_resource_attribution_tags=false'
  -var='agent_iso_file_path=/absolute/path/to/agent.x86_64.iso'
EOF
exit 1
