output "work_dir" {
  description = "Local working directory with Assisted state, manifests, and kubeconfig."
  value       = local.work_dir
}

output "assisted_state" {
  description = "Assisted Installer cluster / infra-env identifiers and paths (null until apply finishes)."
  value = fileexists("${local.work_dir}/assisted-state.json") ? jsondecode(
    file("${local.work_dir}/assisted-state.json")
  ) : null
}

output "kubeconfig_path" {
  description = "Path to the downloaded kubeconfig."
  value       = "${local.work_dir}/kubeconfig"
}

output "kubeconfig" {
  description = "Kubeconfig contents after a successful apply (sensitive)."
  sensitive   = true
  value       = fileexists("${local.work_dir}/kubeconfig") ? file("${local.work_dir}/kubeconfig") : null
}

output "cluster_console_hint" {
  description = "Console hostname pattern once DNS or /etc/hosts is configured."
  value       = "https://console-openshift-console.apps.${var.cluster_name}.${var.base_domain}"
}

output "phases_complete" {
  description = "True after phase4 local-exec has run in this state."
  value       = null_resource.phase4_finish_install.id != ""
}
