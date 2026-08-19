# Agent ISO upload and PAR — connected Agent-based installs only.
# Disconnected installs host rootfs on the webserver (bootArtifactsBaseURL) and upload the
# agent ISO separately (agent_iso_file_path or openshift_image_source_uri).

resource "time_offset" "agent_iso_par_expiry" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  offset_days = var.agent_iso_par_expire_days
}

resource "oci_objectstorage_object" "agent_iso" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  bucket    = oci_objectstorage_bucket.agent_install[0].name
  namespace = local.object_storage_namespace
  object    = local.agent_iso_object_name
  source    = var.agent_iso_file_path

  depends_on = [oci_objectstorage_bucket.agent_install]
}

resource "oci_objectstorage_preauthrequest" "agent_iso" {
  count = local.agent_iso_upload_enabled ? 1 : 0

  namespace    = local.object_storage_namespace
  bucket       = oci_objectstorage_bucket.agent_install[0].name
  name         = local.agent_iso_par_name
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.agent_iso[0].object
  time_expires = time_offset.agent_iso_par_expiry[0].rfc3339

  depends_on = [oci_objectstorage_object.agent_iso]
}

# Disconnected: upload agent ISO object without managed PAR (set openshift_image_source_uri manually
# or extend with a separate PAR resource). Uses the same bucket as webserver config objects.
resource "oci_objectstorage_object" "agent_iso_disconnected" {
  count = var.is_disconnected_installation && var.installation_method == "Agent-based" && var.agent_iso_file_path != "" ? 1 : 0

  bucket    = oci_objectstorage_bucket.agent_install[0].name
  namespace = local.object_storage_namespace
  object    = local.agent_iso_object_name
  source    = var.agent_iso_file_path

  depends_on = [oci_objectstorage_bucket.agent_install]
}

resource "time_offset" "agent_iso_disconnected_par_expiry" {
  count = var.is_disconnected_installation && var.installation_method == "Agent-based" && var.agent_iso_file_path != "" ? 1 : 0

  offset_days = var.agent_iso_par_expire_days
}

resource "oci_objectstorage_preauthrequest" "agent_iso_disconnected" {
  count = var.is_disconnected_installation && var.installation_method == "Agent-based" && var.agent_iso_file_path != "" ? 1 : 0

  namespace    = local.object_storage_namespace
  bucket       = oci_objectstorage_bucket.agent_install[0].name
  name         = local.agent_iso_par_name
  access_type  = "ObjectRead"
  object_name  = oci_objectstorage_object.agent_iso_disconnected[0].object
  time_expires = time_offset.agent_iso_disconnected_par_expiry[0].rfc3339

  depends_on = [oci_objectstorage_object.agent_iso_disconnected]
}
