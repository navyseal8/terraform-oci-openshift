# ROSA-like single apply: Assisted API → ISO/PAR → OCI create-cluster → install → kubeconfig.
# Requires local tools: curl, jq, terraform, oci CLI, and Red Hat offline token + pull secret.

resource "null_resource" "phase1_register_assisted" {
  triggers = {
    cluster_name        = var.cluster_name
    base_domain         = var.base_domain
    openshift_version   = var.openshift_version
    control_plane_count = var.control_plane_count
    compute_count       = var.compute_count
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/01_register_assisted.sh"
    environment = local.common_env
  }
}

resource "null_resource" "phase2_upload_iso_par" {
  depends_on = [null_resource.phase1_register_assisted]

  triggers = {
    phase1 = null_resource.phase1_register_assisted.id
    bucket = var.object_storage_bucket
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/02_upload_iso_par.sh"
    environment = local.common_env
  }
}

resource "null_resource" "phase3_apply_oci_infra" {
  depends_on = [null_resource.phase2_upload_iso_par]

  triggers = {
    phase2              = null_resource.phase2_upload_iso_par.id
    control_plane_count = var.control_plane_count
    compute_count       = var.compute_count
    region              = var.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/03_apply_oci_infra.sh"
    environment = local.common_env
  }
}

resource "null_resource" "phase4_finish_install" {
  depends_on = [null_resource.phase3_apply_oci_infra]

  triggers = {
    phase3 = null_resource.phase3_apply_oci_infra.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/04_finish_install.sh"
    environment = local.common_env
  }
}
