#!/usr/bin/env bash
# Optional destroy helper for Option 2 working state + create-cluster stack.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

workdir_init
STATE_FILE="${WORK_DIR}/assisted-state.json"
CLUSTER_DIR="${REPO_ROOT}/terraform-stacks/create-cluster"
CLUSTER_STATE="${WORK_DIR}/tfstate-create-cluster.tfstate"
TAGS_DIR="${REPO_ROOT}/terraform-stacks/create-resource-attribution-tags"
TAGS_STATE="${WORK_DIR}/tfstate-attribution.tfstate"
DESTROY_ATTRIBUTION_TAGS="${DESTROY_ATTRIBUTION_TAGS:-false}"
DEREGISTER_ASSISTED="${DEREGISTER_ASSISTED:-true}"

if [[ -f "$CLUSTER_STATE" ]]; then
  need_cmd terraform
  log "Destroying create-cluster stack"
  if [[ -f "${WORK_DIR}/create-cluster.tfvars" ]]; then
    terraform -chdir="$CLUSTER_DIR" destroy -input=false -auto-approve \
      -state="$CLUSTER_STATE" \
      -var-file="${WORK_DIR}/create-cluster.tfvars" || true
  else
    log "WARN: create-cluster.tfvars missing; skip terraform destroy"
  fi
fi

if [[ "$DESTROY_ATTRIBUTION_TAGS" == "true" && -f "$TAGS_STATE" ]]; then
  log "Destroying attribution tags (requested)"
  terraform -chdir="$TAGS_DIR" destroy -input=false -auto-approve \
    -state="$TAGS_STATE" \
    -var-file="${WORK_DIR}/attribution.tfvars" || true
fi

if [[ "$DEREGISTER_ASSISTED" == "true" && -f "$STATE_FILE" ]]; then
  cluster_id="$(jq -r '.cluster_id // empty' "$STATE_FILE")"
  infra_env_id="$(jq -r '.infra_env_id // empty' "$STATE_FILE")"
  if [[ -n "$infra_env_id" ]]; then
    log "Deregistering infra-env ${infra_env_id}"
    ai_curl DELETE "/infra-envs/${infra_env_id}" || true
  fi
  if [[ -n "$cluster_id" ]]; then
    log "Deregistering Assisted cluster ${cluster_id}"
    ai_curl DELETE "/clusters/${cluster_id}" || true
  fi
fi

log "Destroy helper finished (work dir left at ${WORK_DIR} for inspection)"
