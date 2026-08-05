locals {
  work_dir = var.work_dir != "" ? var.work_dir : "${path.module}/.work/${var.cluster_name}"

  common_env = {
    WORK_DIR                                        = local.work_dir
    CLUSTER_NAME                                    = var.cluster_name
    BASE_DOMAIN                                     = var.base_domain
    OPENSHIFT_VERSION                               = var.openshift_version
    PULL_SECRET                                     = var.pull_secret
    RH_OFFLINE_TOKEN                                = var.rh_offline_token
    SSH_PUBLIC_KEY                                  = var.public_ssh_key
    CONTROL_PLANE_COUNT                             = tostring(var.control_plane_count)
    COMPUTE_COUNT                                   = tostring(var.compute_count)
    MACHINE_CIDR                                    = var.vcn_cidr
    CLUSTER_NETWORK_CIDR                            = var.cluster_network_cidr
    SERVICE_NETWORK_CIDR                            = var.service_network_cidr
    TENANCY_OCID                                    = var.tenancy_ocid
    COMPARTMENT_OCID                                = var.compartment_ocid
    OCI_COMPARTMENT_OCID                            = var.compartment_ocid
    REGION                                          = var.region
    OCI_REGION                                      = var.region
    TAG_NAMESPACE_COMPARTMENT_OCID_RESOURCE_TAGGING = var.tag_namespace_compartment_ocid_resource_tagging
    OCI_NAMESPACE                                   = var.object_storage_namespace
    OCI_BUCKET                                      = var.object_storage_bucket
    APPLY_ATTRIBUTION_TAGS                          = var.apply_attribution_tags ? "true" : "false"
    VCN_CIDR                                        = var.vcn_cidr
    PUBLIC_CIDR                                     = var.public_cidr
    PRIVATE_CIDR_OCP                                = var.private_cidr_ocp
    PRIVATE_CIDR_BARE_METAL                         = var.private_cidr_bare_metal
    OCI_DRIVER_VERSION                              = var.oci_driver_version
    HOST_WAIT_TIMEOUT_SEC                           = tostring(var.host_wait_timeout_sec)
    INSTALL_WAIT_TIMEOUT_SEC                        = tostring(var.install_wait_timeout_sec)
  }
}
