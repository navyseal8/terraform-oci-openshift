# Option 2 - Agent-based Installer (pipeline-first Terraform)

Terraform execution is intentionally outside shell scripts so it can run in CI/CD pipelines.  
Shell scripts in this folder are only for ISO preparation, disconnected rootfs upload, and post-install monitoring.

Use one Terraform state in `terraform-stacks/create-cluster` with two applies:

- **Phase A (infra only):** network/LB/DNS/IAM/Object Storage (+ webserver for disconnected)
- **Phase B (cluster install):** upload agent ISO, create image/PAR, create OpenShift instances

Connected and disconnected installs use the same Terraform stack with different tfvars.

---

## Connected vs disconnected

| | Connected | Disconnected (air-gapped) |
| --- | --- | --- |
| Example tfvars | `examples/terraform.connected.tfvars.example` | `examples/terraform.disconnected.tfvars.example` |
| `is_disconnected_installation` | `false` | `true` |
| Rootfs source | Internet during install | Local webserver in VCN (`bootArtifactsBaseURL`) |
| Extra OCI resource | none | webserver VM (`webserver_private_ip`) |
| ISO build location | machine with `openshift-install` | bastion with internet |

---

## 0) Prepare tfvars

```bash
# Connected
cp option-2-agent-based/examples/terraform.connected.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars

# OR disconnected
cp option-2-agent-based/examples/terraform.disconnected.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars
```

Update required values in `terraform.tfvars`:

- OCI OCIDs and region
- `cluster_name`, `zone_dns`, `public_ssh_key`, pull secret
- sizing/network CIDRs
- disconnected-only webserver values when `is_disconnected_installation=true`

---

## 1) Terraform phase A (pipeline)

Run phase A from pipeline (or manually in the same way):

```bash
terraform -chdir=terraform-stacks/create-cluster init -input=false
terraform -chdir=terraform-stacks/create-cluster apply -input=false -auto-approve \
  -var='create_openshift_instances=false' \
  -var='agent_iso_file_path='
```

This creates infrastructure and produces outputs used for ISO generation.

---

## 2) Export Terraform outputs to Option 2 work directory

```bash
export CLUSTER_NAME=ocidemo
export WORK_DIR="$PWD/option-2-agent-based/.work/$CLUSTER_NAME"
mkdir -p "$WORK_DIR/openshift"

terraform -chdir=terraform-stacks/create-cluster output -raw agent_config \
  > "$WORK_DIR/agent-config.yaml"
terraform -chdir=terraform-stacks/create-cluster output -raw install_config \
  > "$WORK_DIR/install-config.yaml"
terraform -chdir=terraform-stacks/create-cluster output -raw dynamic_custom_manifest \
  > "$WORK_DIR/openshift/oci-dynamic-custom-manifest.yaml"
```

---

## 3) Build agent ISO (script only, no Terraform)

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/03_build_agent_iso.sh
```

Output ISO path is written to:

- `option-2-agent-based/.work/<cluster>/agent-iso-path.txt`

---

## 4) Disconnected only: upload rootfs to webserver

Only for `is_disconnected_installation=true`.

Get values from your pipeline outputs:

```bash
export WEBSERVER_PRIVATE_IP="$(terraform -chdir=terraform-stacks/create-cluster output -raw webserver_private_ip)"
export BOOT_ARTIFACTS_BASE_URL="$(terraform -chdir=terraform-stacks/create-cluster output -raw boot_artifacts_base_url)"
```

Then upload:

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/02_upload_rootfs_disconnected.sh
```

---

## 5) Terraform phase B (pipeline)

Use the ISO produced in step 3:

```bash
ISO_PATH="$(cat option-2-agent-based/.work/ocidemo/agent-iso-path.txt)"

terraform -chdir=terraform-stacks/create-cluster apply -input=false -auto-approve \
  -var='create_openshift_instances=true' \
  -var='create_resource_attribution_tags=false' \
  -var="agent_iso_file_path=${ISO_PATH}"
```

Useful output:

```bash
terraform -chdir=terraform-stacks/create-cluster output -raw agent_iso_par_url
```

---

## 6) Monitor install

```bash
export CLUSTER_NAME=ocidemo
export WORK_DIR="$PWD/option-2-agent-based/.work/$CLUSTER_NAME"
export KUBECONFIG="$WORK_DIR/auth/kubeconfig"
./option-2-agent-based/scripts/03_monitor_install.sh
```

When autoscaling is enabled:

```bash
./option-2-agent-based/scripts/03_verify_autoscaling.sh
```

---

## Script behavior changes

- `scripts/01_prepare_and_build_iso.sh`: wrapper to ISO build only; no Terraform
- `scripts/02_apply_cluster_install.sh`: retired (returns guidance; no Terraform)
- `scripts/04_apply_phase_b.sh`: retired (returns guidance; no Terraform)

---

## Notes

- Keep `cluster_name` and `zone_dns` consistent between Terraform and installer outputs.
- Do not change node topology after ISO generation unless you regenerate configs and ISO.
- Never commit pull secrets, PAR URLs, kubeadmin password, or kubeconfig artifacts.
