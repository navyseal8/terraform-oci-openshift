# Option 2 — Agent-based Installer (3 steps, 1 Terraform state)

One Terraform state in [`terraform-stacks/create-cluster`](../terraform-stacks/create-cluster) manages:

- Resource attribution tags (optional create on first apply)
- VCN, subnets, NSGs, load balancers, DNS, IAM
- Agent ISO bucket, object upload, and PAR
- Custom images and compute instances

`openshift-install` still runs on your laptop (not in Terraform).

```text
Step 1  terraform apply (infra) + build agent ISO locally
Step 2  terraform apply (upload ISO, PAR, VMs)     — same state file
Step 3  OpenShift agent install on nodes           — automatic; monitor with oc/SSH
```

## Why not “ISO before any Terraform”?

The agent ISO embeds Oracle CCM/CSI manifests that reference OCI resource OCIDs (VCN, subnets, load balancers). Those IDs only exist **after** an infra-only apply. Step 1 therefore does a small Terraform apply first, then builds the ISO from outputs.

You still have **one state file** — step 2 continues the same `terraform-stacks/create-cluster` state.

---

## Prerequisites

| Requirement | Notes |
| --- | --- |
| `terraform` ≥ 1.0 | Single stack: `terraform-stacks/create-cluster` |
| OCI API credentials | `~/.oci/config` |
| `openshift-install` | Matching OCP version |
| Red Hat pull secret | In `terraform.tfvars` |

---

## Setup

```bash
cp option-2-agent-based/examples/terraform.tfvars.example \
   terraform-stacks/create-cluster/terraform.tfvars
# edit OCIDs, region, cluster_name, zone_dns, public_ssh_key, pull secret, shapes
```

---

## Step 1 — Infra + build agent ISO

Creates tags (first run), network, LBs, DNS, IAM, and the Object Storage bucket. Then runs `openshift-install` locally.

```bash
export CLUSTER_NAME=jemdemo
./option-2-agent-based/scripts/01_prepare_and_build_iso.sh
```

Or manually:

```bash
cd terraform-stacks/create-cluster
terraform init && terraform apply \
  -var="create_openshift_instances=false" \
  -var="agent_iso_file_path="

export CLUSTER_NAME=jemdemo
export WORK_DIR=$PWD/../../option-2-agent-based/.work/$CLUSTER_NAME
../../option-2-agent-based/scripts/03_build_agent_iso.sh
```

After the first successful apply, set `create_resource_attribution_tags = false` in `terraform.tfvars` (tags already exist).

---

## Step 2 — Upload ISO, PAR, and create VMs (same state)

```bash
export CLUSTER_NAME=jemdemo
./option-2-agent-based/scripts/02_apply_cluster_install.sh
```

This sets `agent_iso_file_path`, `create_openshift_instances = true`, runs `terraform apply`, and writes `$WORK_DIR/iso-par-url.txt` from the `agent_iso_par_url` output.

Or manually:

```bash
cd terraform-stacks/create-cluster
# set in terraform.tfvars:
#   create_openshift_instances = true
#   agent_iso_file_path        = "/path/to/.work/jemdemo/agent.x86_64.iso"
#   create_resource_attribution_tags = false
terraform apply
```

---

## Step 3 — OpenShift installs

Instances boot from the agent ISO. Installation runs on the rendezvous node (`rendezvous_ip`).

```bash
export CLUSTER_NAME=jemdemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export KUBECONFIG=$WORK_DIR/auth/kubeconfig

./option-2-agent-based/scripts/03_monitor_install.sh
oc get nodes
oc get clusteroperators
```

Kubeadmin password: `$WORK_DIR/auth/kubeadmin-password` (created during step 1 ISO build).

Console (after DNS or `/etc/hosts` from `terraform output etc_hosts_entry`):

```text
https://console-openshift-console.apps.<cluster_name>.<zone_dns>
```

---

## Key `terraform.tfvars` variables

| Variable | Apply 1 (infra) | Apply 2 (install) |
| --- | --- | --- |
| `create_resource_attribution_tags` | `true` (once) | `false` |
| `create_openshift_instances` | `false` | `true` |
| `agent_iso_file_path` | `""` | path to `agent.x86_64.iso` |
| `object_storage_bucket` | e.g. `openshift-agent-iso` | same |

`openshift_image_source_uri` is **not** needed when `agent_iso_file_path` is set — Terraform creates the PAR.

---

## Layout

```
option-2-agent-based/
  README.md
  examples/
    terraform.tfvars.example      # single config for create-cluster
  scripts/
    01_prepare_and_build_iso.sh
    02_apply_cluster_install.sh
    03_build_agent_iso.sh
    03_monitor_install.sh
  terraform/
    agent-iso-storage/            # deprecated; use create-cluster agent_iso.tf
```

State file: `terraform-stacks/create-cluster/terraform.tfstate`

---

## Notes

- Do not change `cluster_name`, `zone_dns`, `rendezvous_ip`, or node counts after generating the agent ISO.
- Never commit pull secrets, PAR URLs, or `auth/kubeadmin-password`.
- Legacy 4-step scripts (`03_create_agent_iso_par.sh`, `04_apply_phase_b.sh`) wrap the new flow for compatibility.
