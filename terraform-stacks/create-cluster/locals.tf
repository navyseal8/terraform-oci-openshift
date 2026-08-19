data "oci_identity_regions" "regions" {
}

data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

locals {
  region_map = {
    for r in data.oci_identity_regions.regions.regions :
    r.key => r.name
  }

  current_region_key = [
    for r in data.oci_identity_regions.regions.regions :
    r.key if r.name == var.region
  ][0]

  home_region = local.region_map[data.oci_identity_tenancy.tenancy.home_region_key]

  is_control_plane_iscsi_type = can(regex("^BM\\..*$", var.control_plane_shape))
  is_compute_iscsi_type       = can(regex("^BM\\..*$", var.compute_shape))
  is_autoscaler_bm_shape      = can(regex("^BM\\..*$", var.autoscaler_node_shape))
  effective_compute_count     = var.use_autoscaling_operator ? 0 : var.compute_count

  apps_subnet_id                   = var.enable_public_apps_lb ? module.network.op_subnet_public : module.network.op_subnet_private_ocp
  apps_security_list_id            = var.enable_public_apps_lb ? module.network.op_security_list_public : module.network.op_security_list_private
  existing_vcn_compartment_ocid    = var.use_existing_network ? var.vcn_compartment_ocid : null
  existing_subnet_compartment_ocid = var.use_existing_network ? var.subnet_compartment_ocid : null

  openshift_installer_version = var.set_openshift_installer_version ? var.openshift_installer_version : "latest"

  # how long resource creation will be paused to allow for newly created tagging resources to reach consistency
  wait_for_new_tag_consistency_wait_time = "30s"

  openshift_resource_attribution_tag = var.create_resource_attribution_tags ? module.resource_attribution_tags_create[0].openshift_resource_attribution_tag : module.resource_attribution_tags_find[0].openshift_resource_attribution_tag

  agent_install_bucket_enabled = var.installation_method == "Agent-based" && var.object_storage_bucket != ""
  agent_iso_bucket_enabled     = local.agent_install_bucket_enabled && !var.is_disconnected_installation
  agent_iso_upload_enabled     = local.agent_iso_bucket_enabled && var.agent_iso_file_path != ""
  agent_iso_object_name    = var.agent_iso_object_name != "" ? var.agent_iso_object_name : "${var.cluster_name}-agent.iso"
  agent_iso_par_name       = var.agent_iso_par_name != "" ? var.agent_iso_par_name : "${var.cluster_name}-agent-par"

  openshift_image_source_uri = local.agent_iso_upload_enabled ? "https://objectstorage.${var.region}.oraclecloud.com${oci_objectstorage_preauthrequest.agent_iso[0].access_uri}" : (
    var.is_disconnected_installation && var.agent_iso_file_path != "" ? "https://objectstorage.${var.region}.oraclecloud.com${oci_objectstorage_preauthrequest.agent_iso_disconnected[0].access_uri}" : var.openshift_image_source_uri
  )
}
