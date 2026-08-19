# Option 2 — Agent-based Installer (3 steps, 1 Terraform state)

One Terraform state in [`terraform-stacks/create-cluster`](../terraform-stacks/create-cluster) manages attribution tags, network, LBs, DNS, IAM, Object Storage, and VMs.

Choose **connected** or **disconnected (air-gapped)** — same state file, different `terraform.tfvars`:

| | Connected | Disconnected (air-gapped) |
| --- | --- | --- |
| Example tfvars | [`examples/terraform.connected.tfvars.example`](examples/terraform.connected.tfvars.example) | [`examples/terraform.disconnected.tfvars.example`](examples/terraform.disconnected.tfvars.example) |
| `is_disconnected_installation` | `false` | `true` |
| Rootfs source | Downloaded from internet during install | HTTP webserver in VCN (`bootArtifactsBaseURL`) |
| Extra OCI resource | — | Webserver VM (`webserver_private_ip`) |
| ISO build | Local machine (`openshift-install`) | Bastion with internet (same tool) |

```text
Step 1  terraform apply (infra) + build agent ISO locally (+ disconnected: upload rootfs)
Step 2  terraform apply (ISO upload, PAR, VMs)     — same state
Step 3  OpenShift agent install on nodes
```

Oracle / Red Hat reference: [Agent-based Installer on OCI](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/installing_on_oci/installing-oci-agent-based-installer).

---

## Setup

```bash
# Connected
cp option-2-agent-based/examples/terraform.connected.tfvars.example \
   terraform-stacks/create-cluster/terraform.tfvars

# OR disconnected (air-gapped)
cp option-2-agent-based/examples/terraform.disconnected.tfvars.example \
   terraform-stacks/create-cluster/terraform.tfvars

# edit OCIDs, region, cluster_name, zone_dns, public_ssh_key, pull secret, shapes
```

---

## Part A — Connected installation

Nodes can reach the internet during install. No webserver VM. Terraform creates the Object Storage bucket, uploads the agent ISO, and creates a PAR.

### Step 1 — Infra + build ISO

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/01_prepare_and_build_iso.sh
```

Creates network/LB/DNS/IAM/bucket (`create_openshift_instances=false`), then runs `openshift-install agent create image`.

### Step 2 — Upload ISO, PAR, VMs

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/02_apply_cluster_install.sh
```

### Step 3 — Monitor

```bash
export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export KUBECONFIG=$WORK_DIR/auth/kubeconfig
./option-2-agent-based/scripts/03_monitor_install.sh
```

---

## Part B — Disconnected (air-gapped) installation

Cluster nodes **cannot** reach the internet. Terraform provisions a **webserver** VM that serves `agent.x86_64-rootfs.img` at `http://<webserver_private_ip>/` (`bootArtifactsBaseURL` in `agent-config.yaml`).

### Step 1 — Infra + build ISO + upload rootfs

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/01_prepare_and_build_iso.sh
```

Infra apply creates the webserver, bucket, and uploads install manifests to Object Storage.

Upload the rootfs image to the webserver (from your bastion):

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/02_upload_rootfs_disconnected.sh
```

Verify from a node subnet or jump host:

```bash
curl -I "http://$(terraform -chdir=terraform-stacks/create-cluster output -raw webserver_private_ip)/agent.x86_64-rootfs.img"
```

### Step 2 — Upload agent ISO, PAR, VMs

Same script as connected — Terraform uploads the minimal agent ISO and creates VMs:

```bash
export CLUSTER_NAME=ocidemo
./option-2-agent-based/scripts/02_apply_cluster_install.sh
```

### Step 3 — Monitor

Same as connected (step 3 above).

---

## Key variables

| Variable | Connected | Disconnected |
| --- | --- | --- |
| `is_disconnected_installation` | `false` | `true` |
| `object_storage_bucket` | required | required |
| `webserver_private_ip` | — | required (e.g. `10.0.0.200`) |
| `webserver_shape` / `webserver_ocpus` | — | set per sizing |
| `set_openshift_installer_version` | optional | recommended (`true` + pinned version) |

### Apply 1 vs apply 2 toggles (both paths)

| Variable | Apply 1 (infra) | Apply 2 (install) |
| --- | --- | --- |
| `create_resource_attribution_tags` | `true` (once) | `false` |
| `create_openshift_instances` | `false` | `true` |
| `agent_iso_file_path` | `""` | path to `agent.x86_64.iso` |

---

## Why infra apply before ISO build?

The agent ISO embeds Oracle CCM/CSI manifests with OCI resource OCIDs (VCN, subnets, load balancers). Those exist only after the infra-only apply. Both connected and disconnected paths use the same constraint.

---

## Layout

```
option-2-agent-based/
  README.md
  examples/
    terraform.connected.tfvars.example
    terraform.disconnected.tfvars.example
  scripts/
    01_prepare_and_build_iso.sh
    02_apply_cluster_install.sh
    02_upload_rootfs_disconnected.sh   # air-gapped only
    03_build_agent_iso.sh
    03_monitor_install.sh
```

State: `terraform-stacks/create-cluster/terraform.tfstate`

---

## Notes

- Do not change `cluster_name`, `zone_dns`, `rendezvous_ip`, or node counts after generating the agent ISO.
- Disconnected: ensure NSGs/security lists allow cluster nodes to reach `webserver_private_ip:80`.
- Never commit pull secrets, PAR URLs, or `auth/kubeadmin-password`.
