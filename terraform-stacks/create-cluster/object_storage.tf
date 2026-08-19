data "oci_objectstorage_namespace" "tenancy" {
  compartment_id = var.compartment_ocid
}

locals {
  object_storage_namespace = var.object_storage_namespace != "" ? var.object_storage_namespace : data.oci_objectstorage_namespace.tenancy.namespace
}
