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

### Step 3 — Monitor (+ autoscaling if enabled)

```bash
export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export KUBECONFIG=$WORK_DIR/auth/kubeconfig
./option-2-agent-based/scripts/03_monitor_install.sh

# when use_autoscaling_operator = true:
./option-2-agent-based/scripts/03_verify_autoscaling.sh
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

### Step 3 — Monitor (+ autoscaling if enabled)

Same as connected — include `03_verify_autoscaling.sh` when autoscaling is enabled.

---

## OCI Autoscaling (both connected and disconnected)

The vendored stack can deploy the **OCI OpenShift Autoscaler Operator** (CAPOCI + cluster-autoscaler). It uses **instance principal** on control plane nodes to call OCI APIs and create/delete worker instances.

### Enable in `terraform.tfvars`

Set before **apply 1** (manifests are baked into the agent ISO):

```hcl
use_autoscaling_operator      = true
autoscaler_node_minimum_count = 1    # recommend >= 1 for a usable cluster
autoscaler_node_maximum_count = 5
autoscaler_node_shape         = "VM.Standard.E5.Flex"
autoscaler_node_ocpus         = 6
autoscaler_node_memory        = 32
# autoscaler_pool_identifier  = ""   # optional, max 5 chars

# Reuses the agent ISO PAR automatically when left empty:
autoscaler_node_image_source_uri = ""
```

When `use_autoscaling_operator = true`, **`compute_count` is ignored** (workers are autoscaled, not statically provisioned).

Autoscaling manifests (`08-autoscaling-operator.yml` + runtime bundle) are included in `dynamic_custom_manifest` at ISO build time. After install converges, the operator activates CAPOCI and creates `OCIClusterAutoscaler` resources.

### Step 3 — Verify autoscaling

```bash
export CLUSTER_NAME=ocidemo
export KUBECONFIG=$PWD/option-2-agent-based/.work/$CLUSTER_NAME/auth/kubeconfig
./option-2-agent-based/scripts/03_verify_autoscaling.sh
```

Check pods:

```bash
oc get pods -n oci-openshift-autoscaling-operator
oc get ociclusterautoscaler -n oci-openshift-autoscaling-operator
```

---

## OCI IAM permissions for autoscaling

Terraform **creates** the dynamic groups and policies below in `shared_modules/iam/`. The autoscaler (CAPOCI controller on control plane nodes) authenticates via **instance principal** using the control plane dynamic group.

### Dynamic groups (tenancy level)

| Dynamic group | Matching rule |
| --- | --- |
| `{cluster_name}_control_plane_nodes` | Instances in cluster compartment tagged `instance_role=control_plane` |
| `{cluster_name}_compute_nodes` | Instances in cluster compartment tagged `instance_role=compute` |

CAPOCI runs on the control plane and uses **`{cluster_name}_control_plane_nodes`**.

### Policies created by Terraform

**Cluster compartment** (`policy_openshift_control_plane_nodes`):

```text
Allow dynamic-group <cluster>_control_plane_nodes to manage volume-family in compartment id <compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage instance-family in compartment id <compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage security-lists in compartment id <compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage virtual-network-family in compartment id <compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage load-balancers in compartment id <compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage objects in compartment id <compartment_ocid>
```

**Tenancy** (`policy_openshift_control_plane_nodes_tags`):

```text
Allow dynamic-group <cluster>_control_plane_nodes to use tag-namespaces in tenancy
```

**VCN / subnet compartment** (only when VCN or subnets live outside the cluster compartment):

```text
Allow dynamic-group <cluster>_control_plane_nodes to manage security-lists in compartment id <vcn_compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage virtual-network-family in compartment id <vcn_compartment_ocid>
Allow dynamic-group <cluster>_control_plane_nodes to manage virtual-network-family in compartment id <subnet_compartment_ocid>
```

### Resource attribution tags (mandatory)

Autoscaling nodes must carry attribution tags. Before any cluster apply:

1. `openshift-tags` namespace + `openshift-resource=openshift-resource-infra` defined tag must exist (`create_resource_attribution_tags = true` on first apply).
2. Control plane dynamic group must **`use tag-namespaces`** in the compartment that owns those tags (Terraform policy above).

### Terraform operator permissions (who runs `terraform apply`)

The identity running Terraform needs standard `create-cluster` permissions plus ability to **import custom images** from Object Storage PAR URLs (agent ISO and autoscaler image).

---

## Connected vs disconnected — autoscaling differences

| Concern | Connected | Disconnected (air-gapped) |
| --- | --- | --- |
| **OCI API access from control plane** | Instance principal → OCI APIs (route via NAT or service gateway) | **Same IAM policies**; nodes must reach OCI endpoints (use **service gateway** for `oci-*` services) |
| **CAPOCI / operator images** | Pulled from `quay.io`, `ghcr.io`, `github.com` during install | Must be **mirrored** to internal registry or pre-loaded; activate job fetches CAPOCI YAML from GitHub |
| **cluster-autoscaler chart** | Fetched from `kubernetes.github.io/autoscaler` by operator | Mirror Helm chart repo or vendor offline |
| **Autoscaler node image** | Terraform imports from agent ISO PAR (`autoscaler_node_image_source_uri`) | Same — PAR/object in your bucket; no public internet needed for import |
| **BM autoscale shapes** | Set `autoscaler_node_shape` to `BM.*`; needs bare metal subnet + iSCSI tags | Same; ensure webserver/rootfs path still valid |

**Summary:** OCI **IAM/instance-principal permissions are identical**. The difference is **network egress**: connected clusters reach public registries directly; disconnected clusters need mirrors and service-gateway access to OCI APIs.

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
| `use_autoscaling_operator` | set before apply 1 | unchanged |
| `autoscaler_node_*` | set before apply 1 | unchanged |

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
    03_verify_autoscaling.sh
```

State: `terraform-stacks/create-cluster/terraform.tfstate`

---

## Notes

- Do not change `cluster_name`, `zone_dns`, `rendezvous_ip`, or node counts after generating the agent ISO.
- When autoscaling is enabled, set `autoscaler_node_minimum_count >= 1` unless you intentionally start with zero workers.
- Disconnected: ensure NSGs/security lists allow cluster nodes to reach `webserver_private_ip:80`.
- Never commit pull secrets, PAR URLs, or `auth/kubeadmin-password`.
