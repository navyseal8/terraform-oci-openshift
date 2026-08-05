variable "cluster_name" {
  type        = string
  description = "OpenShift cluster name (DNS-compatible). Must match Assisted Installer naming rules."
}

variable "base_domain" {
  type        = string
  description = "Base DNS domain (Assisted base_dns_domain / Terraform zone_dns)."
}

variable "openshift_version" {
  type        = string
  description = "OpenShift version for Assisted Installer (e.g. 4.16 or 4.16.3)."
  default     = "4.16"
}

variable "pull_secret" {
  type        = string
  description = "Red Hat pull secret JSON string."
  sensitive   = true
}

variable "rh_offline_token" {
  type        = string
  description = "Red Hat offline token used to mint Assisted Installer API access tokens."
  sensitive   = true
}

variable "public_ssh_key" {
  type        = string
  description = "SSH public key installed on cluster nodes."
}

variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID."
}

variable "compartment_ocid" {
  type        = string
  description = "OCI compartment OCID for the cluster."
}

variable "region" {
  type        = string
  description = "OCI region (prefer multi-AD), e.g. us-ashburn-1."
}

variable "tag_namespace_compartment_ocid_resource_tagging" {
  type        = string
  description = "Compartment OCID for openshift-tags attribution namespace."
}

variable "object_storage_namespace" {
  type        = string
  description = "OCI Object Storage namespace (tenancy namespace)."
}

variable "object_storage_bucket" {
  type        = string
  description = "Bucket name for the discovery ISO (created if missing)."
}

variable "control_plane_count" {
  type        = number
  description = "Number of control-plane nodes."
  default     = 3
}

variable "compute_count" {
  type        = number
  description = "Number of worker/compute nodes."
  default     = 2
}

variable "apply_attribution_tags" {
  type        = bool
  description = "Apply create-resource-attribution-tags before create-cluster."
  default     = true
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "private_cidr_ocp" {
  type    = string
  default = "10.0.16.0/20"
}

variable "private_cidr_bare_metal" {
  type    = string
  default = "10.0.32.0/20"
}

variable "cluster_network_cidr" {
  type        = string
  description = "Pod / clusterNetwork CIDR."
  default     = "10.128.0.0/14"
}

variable "service_network_cidr" {
  type        = string
  description = "Service network CIDR."
  default     = "172.30.0.0/16"
}

variable "oci_driver_version" {
  type    = string
  default = "v1.34.0"
}

variable "work_dir" {
  type        = string
  description = "Local working directory for ISO, state JSON, kubeconfig (gitignored)."
  default     = ""
}

variable "host_wait_timeout_sec" {
  type    = number
  default = 3600
}

variable "install_wait_timeout_sec" {
  type    = number
  default = 7200
}
