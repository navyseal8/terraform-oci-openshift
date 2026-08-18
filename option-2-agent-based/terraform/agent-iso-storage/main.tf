data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.compartment_ocid
}

resource "time_offset" "par_expiry" {
  offset_days = var.par_expire_days
}

locals {
  namespace         = data.oci_objectstorage_namespace.tenancy.namespace
  agent_iso_object  = var.agent_iso_object_name != "" ? var.agent_iso_object_name : "${var.cluster_name}-agent.iso"
  par_name          = var.par_name != "" ? var.par_name : "${var.cluster_name}-agent-par"
  agent_iso_par_url = "https://objectstorage.${var.region}.oraclecloud.com${oci_objectstorage_preauthrequest.agent_iso.access_uri}"
}

resource "oci_objectstorage_bucket" "agent_iso" {
  compartment_id = var.compartment_ocid
  name           = var.object_storage_bucket
  namespace      = local.namespace
  storage_tier   = var.storage_tier
  versioning     = "Disabled"
}

resource "oci_objectstorage_object" "agent_iso" {
  bucket    = oci_objectstorage_bucket.agent_iso.name
  namespace = local.namespace
  object    = local.agent_iso_object
  source    = var.agent_iso_file_path
}

resource "oci_objectstorage_preauthrequest" "agent_iso" {
  namespace    = local.namespace
  bucket       = oci_objectstorage_bucket.agent_iso.name
  name         = local.par_name
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.agent_iso.object
  time_expires = time_offset.par_expiry.rfc3339

  depends_on = [oci_objectstorage_object.agent_iso]
}
