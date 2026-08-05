#!/usr/bin/env bash
# Single entrypoint for Option 2 (ROSA-like). Equivalent to: terraform apply
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

chmod +x scripts/*.sh

if [[ ! -f terraform.tfvars && ! -f terraform.tfvars.json ]]; then
  echo "Copy terraform.tfvars.example to terraform.tfvars and fill secrets first." >&2
  exit 1
fi

terraform init -input=false
terraform apply -input=false "$@"
