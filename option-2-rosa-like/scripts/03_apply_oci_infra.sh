#!/usr/bin/env bash
# Phase 3: Apply vendored create-cluster stack (and optional attribution tags).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

need_cmd terraform

workdir_init
STATE_FILE="${WORK_DIR}/assisted-state.json"
PAR_FILE="${WORK_DIR}/iso-par-url.txt"
[[ -f "$STATE_FILE" && -f "$PAR_FILE" ]] || {
  echo "ERROR: run phases 01 and 02 first" >&2
  exit 1
}

CLUSTER_NAME="$(jq -er '.cluster_name' "$STATE_FILE")"
BASE_DOMAIN="$(jq -er '.base_domain' "$STATE_FILE")"
ISO_PAR_URL="$(tr -d '\n' <"$PAR_FILE")"

TENANCY_OCID="${TENANCY_OCID:?}"
COMPARTMENT_OCID="${COMPARTMENT_OCID:?}"
REGION="${REGION:?}"
TAG_COMPARTMENT_OCID="${TAG_NAMESPACE_COMPARTMENT_OCID_RESOURCE_TAGGING:?}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:?}"
CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"
COMPUTE_COUNT="${COMPUTE_COUNT:-2}"
APPLY_ATTRIBUTION_TAGS="${APPLY_ATTRIBUTION_TAGS:-true}"

VCN_CIDR="${VCN_CIDR:-10.0.0.0/16}"
PUBLIC_CIDR="${PUBLIC_CIDR:-10.0.0.0/20}"
PRIVATE_CIDR_OCP="${PRIVATE_CIDR_OCP:-10.0.16.0/20}"
PRIVATE_CIDR_BARE_METAL="${PRIVATE_CIDR_BARE_METAL:-10.0.32.0/20}"
CLUSTER_NETWORK_CIDR="${CLUSTER_NETWORK_CIDR:-10.128.0.0/14}"
SERVICE_NETWORK_CIDR="${SERVICE_NETWORK_CIDR:-172.30.0.0/16}"
OCI_DRIVER_VERSION="${OCI_DRIVER_VERSION:-v1.34.0}"

TAGS_DIR="${REPO_ROOT}/terraform-stacks/create-resource-attribution-tags"
CLUSTER_DIR="${REPO_ROOT}/terraform-stacks/create-cluster"
TAGS_STATE="${WORK_DIR}/tfstate-attribution.tfstate"
CLUSTER_STATE="${WORK_DIR}/tfstate-create-cluster.tfstate"
MANIFEST_OUT="${WORK_DIR}/dynamic_custom_manifest.yml"
INFRA_OUT_JSON="${WORK_DIR}/oci-infra-outputs.json"

if [[ "$APPLY_ATTRIBUTION_TAGS" == "true" ]]; then
  log "Applying create-resource-attribution-tags (once per tenancy is enough)"
  cat >"${WORK_DIR}/attribution.tfvars" <<EOF
tenancy_ocid                                    = "${TENANCY_OCID}"
tag_namespace_compartment_ocid_resource_tagging = "${TAG_COMPARTMENT_OCID}"
EOF
  terraform -chdir="$TAGS_DIR" init -input=false >/dev/null
  terraform -chdir="$TAGS_DIR" apply -input=false -auto-approve \
    -state="$TAGS_STATE" \
    -var-file="${WORK_DIR}/attribution.tfvars"
fi

log "Writing create-cluster tfvars"
cat >"${WORK_DIR}/create-cluster.tfvars" <<EOF
tenancy_ocid     = "${TENANCY_OCID}"
compartment_ocid = "${COMPARTMENT_OCID}"
region           = "${REGION}"
tag_namespace_compartment_ocid_resource_tagging = "${TAG_COMPARTMENT_OCID}"

cluster_name        = "${CLUSTER_NAME}"
zone_dns            = "${BASE_DOMAIN}"
installation_method = "Assisted"
public_ssh_key      = <<EOT
${SSH_PUBLIC_KEY}
EOT
openshift_image_source_uri = "${ISO_PAR_URL}"

control_plane_count                = ${CONTROL_PLANE_COUNT}
distribute_cp_instances_across_ads = true
distribute_cp_instances_across_fds = true
compute_count                            = ${COMPUTE_COUNT}
distribute_compute_instances_across_ads  = true
distribute_compute_instances_across_fds  = true

vcn_cidr                = "${VCN_CIDR}"
public_cidr             = "${PUBLIC_CIDR}"
private_cidr_ocp        = "${PRIVATE_CIDR_OCP}"
private_cidr_bare_metal = "${PRIVATE_CIDR_BARE_METAL}"
cluster_network_cidr_block = "${CLUSTER_NETWORK_CIDR}"
service_network_cidr_block = "${SERVICE_NETWORK_CIDR}"
oci_driver_version         = "${OCI_DRIVER_VERSION}"
EOF

log "Applying create-cluster stack"
terraform -chdir="$CLUSTER_DIR" init -input=false >/dev/null
terraform -chdir="$CLUSTER_DIR" apply -input=false -auto-approve \
  -state="$CLUSTER_STATE" \
  -var-file="${WORK_DIR}/create-cluster.tfvars"

terraform -chdir="$CLUSTER_DIR" output -state="$CLUSTER_STATE" -json >"$INFRA_OUT_JSON"
terraform -chdir="$CLUSTER_DIR" output -state="$CLUSTER_STATE" -raw dynamic_custom_manifest >"$MANIFEST_OUT"

jq --arg manifest "$MANIFEST_OUT" \
  '. + {manifest_path: $manifest, oci_infra_outputs: "'"$INFRA_OUT_JSON"'"}' \
  "$STATE_FILE" >"${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

log "OCI infra applied; manifest at ${MANIFEST_OUT}"
cat "$INFRA_OUT_JSON"
