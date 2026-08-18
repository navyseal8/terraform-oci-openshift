# Agent ISO bucket, upload, and PAR — Agent-based connected installs (Option 2).
# Set agent_iso_file_path on the second apply after building the ISO locally.

data "oci_objectstorage_namespace" "agent_iso" {
  count = local.agent_iso_bucket_enabled ? 1 : 0

  compartment_id = var.compartment_ocid
}

resource "time_offset" "agent_iso_par_expiry" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  offset_days = var.agent_iso_par_expire_days
}

resource "oci_objectstorage_bucket" "agent_iso" {
  count = local.agent_iso_bucket_enabled ? 1 : 0

  compartment_id = var.compartment_ocid
  name           = var.object_storage_bucket
  namespace      = data.oci_objectstorage_namespace.agent_iso[0].namespace
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

resource "oci_objectstorage_object" "agent_iso" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  bucket    = oci_objectstorage_bucket.agent_iso[0].name
  namespace = data.oci_objectstorage_namespace.agent_iso[0].namespace
  object    = local.agent_iso_object_name
  source    = var.agent_iso_file_path
}

resource "oci_objectstorage_preauthrequest" "agent_iso" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  namespace    = data.oci_objectstorage_namespace.agent_iso[0].namespace
  bucket       = oci_objectstorage_bucket.agent_iso[0].name
  name         = local.agent_iso_par_name
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.agent_iso[0].object
  time_expires = time_offset.agent_iso_par_expiry[0].rfc3339

  depends_on = [oci_objectstorage_object.agent_iso]
}
