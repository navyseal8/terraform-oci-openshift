variable "region" {
  type        = string
  description = "OCI region for the Object Storage bucket (e.g. ap-singapore-1)."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment that owns the agent ISO bucket."
}

variable "cluster_name" {
  type        = string
  description = "OpenShift cluster name; used in object and PAR names."
}

variable "object_storage_bucket" {
  type        = string
  description = "Name of the Object Storage bucket for the agent ISO."
}

variable "agent_iso_file_path" {
  type        = string
  description = "Local path to agent*.iso built by openshift-install (step 3 build script)."
}

variable "agent_iso_object_name" {
  type        = string
  default     = ""
  description = "Object name in the bucket. Defaults to <cluster_name>-agent.iso."
}

variable "par_name" {
  type        = string
  default     = ""
  description = "Pre-authenticated request name. Defaults to <cluster_name>-agent-par."
}

variable "par_expire_days" {
  type        = number
  default     = 7
  description = "PAR lifetime in days from apply time."
}

variable "storage_tier" {
  type        = string
  default     = "Standard"
  description = "Object Storage bucket storage tier."
}
