locals {
  openshift_resource_attribution_namespace = var.openshift_attribution_tag_namespace
  openshift_resource_attribution_key       = var.openshift_attribution_tag_key
}

output "openshift_resource_attribution_tag" {
  value = {
    "${local.openshift_resource_attribution_namespace}.${local.openshift_resource_attribution_key}" = var.openshift_attribution_tag_value
  }
}
