output "object_storage_namespace" {
  description = "Tenancy Object Storage namespace."
  value       = local.namespace
}

output "object_storage_bucket" {
  description = "Bucket hosting the agent ISO."
  value       = oci_objectstorage_bucket.agent_iso.name
}

output "agent_iso_object_name" {
  description = "Object key for the uploaded agent ISO."
  value       = oci_objectstorage_object.agent_iso.object
}

output "agent_iso_par_url" {
  description = "ObjectRead PAR URL for openshift_image_source_uri in create-cluster phase B."
  value       = local.agent_iso_par_url
  sensitive   = true
}

output "agent_iso_par_expires" {
  description = "PAR expiration time (RFC3339)."
  value       = time_offset.par_expiry.rfc3339
}
