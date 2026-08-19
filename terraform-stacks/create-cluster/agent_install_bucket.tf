# Shared Object Storage bucket for Agent-based installs (connected and disconnected).
# Webserver config objects and (connected) agent ISO objects both use this bucket.

resource "oci_objectstorage_bucket" "agent_install" {
  count = local.agent_install_bucket_enabled ? 1 : 0

  compartment_id = var.compartment_ocid
  name           = var.object_storage_bucket
  namespace      = local.object_storage_namespace
  storage_tier   = "Standard"
  versioning     = "Disabled"
}
