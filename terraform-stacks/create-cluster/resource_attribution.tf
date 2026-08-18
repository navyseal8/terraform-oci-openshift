# Resource attribution tags — create once per tenancy, or find existing tags.
module "resource_attribution_tags_find" {
  count  = var.create_resource_attribution_tags ? 0 : 1
  source = "./shared_modules/resource_attribution_tags/find_resource_tags"

  providers = {
    oci = oci.home
  }

  tag_namespace_compartment_ocid_resource_tagging = var.tag_namespace_compartment_ocid_resource_tagging
}

module "resource_attribution_tags_create" {
  count  = var.create_resource_attribution_tags ? 1 : 0
  source = "./shared_modules/resource_attribution_tags/create_resource_tags"

  providers = {
    oci = oci.home
  }

  tag_namespace_compartment_ocid_resource_tagging = var.tag_namespace_compartment_ocid_resource_tagging
}
