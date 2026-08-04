# OpenShift on OCI (Terraform)

Terraform stacks to provision a Red Hat OpenShift Container Platform cluster on Oracle Cloud Infrastructure using the **Assisted Installer** path.

Vendored from [oracle-quickstart/oci-openshift](https://github.com/oracle-quickstart/oci-openshift) **v1.6.0**. See [terraform-stacks/VENDOR.md](terraform-stacks/VENDOR.md).

## Target topology

| Role | Count | Placement |
| --- | --- | --- |
| Control plane | 3 | Round-robin across Availability Domains |
| Workers (compute) | 2 | Spread across ADs / FDs |

Cloud provider integrations (via stack IAM + `dynamic_custom_manifest`):

- **Load balancers** — OCI flexible LBs for `api`, `api-int`, and `*.apps` (CCM)
- **Storage** — OCI Block Volumes (CSI)
- **Identity** — Instance Principals (dynamic groups + policies), not AWS-style OIDC/IRSA

Example inputs: [examples/ha-3cp-2workers.tfvars.example](examples/ha-3cp-2workers.tfvars.example).

## Network CIDRs

Defaults (pinned in the example tfvars) must not overlap. Use the **same** values in Assisted Installer networking.

| Network | Terraform variable | CIDR |
| --- | --- | --- |
| Machine / VCN | `vcn_cidr` | `10.0.0.0/16` |
| Public subnet | `public_cidr` | `10.0.0.0/20` |
| Private OCP subnet | `private_cidr_ocp` | `10.0.16.0/20` |
| Private BM subnet | `private_cidr_bare_metal` | `10.0.32.0/20` |
| **Pod / clusterNetwork** | `cluster_network_cidr_block` | **`10.128.0.0/14`** |
| **Service network** | `service_network_cidr_block` | **`172.30.0.0/16`** |

Change these only if they collide with an existing peered VCN or on-prem range.

## Prerequisites

- OCI tenancy with permissions to create VCN, compute, LB, DNS, IAM, and tags
- Prefer a **multi-AD** region so three control-plane nodes land in three Availability Domains
- Child compartment (recommended) and an Object Storage bucket for the discovery ISO
- Red Hat account, pull secret, and Assisted Installer access
- DNS base domain for `zone_dns`
- SSH public key

## Apply order

### 1. Resource attribution tags (once per tenancy)

Skipping this causes bootstrap failures. The stack creates `openshift-tags` / `openshift-resource=openshift-resource-infra`.

```bash
cp examples/resource-attribution-tags.tfvars.example \
  terraform-stacks/create-resource-attribution-tags/terraform.tfvars
# edit REPLACE_* values

cd terraform-stacks/create-resource-attribution-tags
terraform init
terraform apply
```

Note the compartment OCID used for the tag namespace; pass it as `tag_namespace_compartment_ocid_resource_tagging` to `create-cluster`.

You can also apply this stack via [OCI Resource Manager](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Concepts/resourcemanager.htm) using the stack folder or the upstream zip release.

### 2. Assisted Installer (Red Hat Hybrid Cloud Console)

1. Create a cluster with partner platform **Oracle Cloud Infrastructure** (requires custom manifests).
2. Set **Cluster name** = Terraform `cluster_name` and **Base domain** = Terraform `zone_dns`.
3. Set Machine / Cluster (pod) / Service CIDRs to match the table above.
4. Generate the **Minimal** discovery ISO.

Docs: [Installing on Oracle Distributed Cloud with Assisted Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_oracle_distributed_cloud/installing-oci-assisted-installer).

### 3. Upload ISO and create a PAR

1. Upload the discovery ISO to your Object Storage bucket.
2. Create a Pre-Authenticated Request (PAR) URL for the object.
3. Set `openshift_image_source_uri` in your create-cluster tfvars to that PAR URL.

### 4. Create cluster infrastructure

```bash
cp examples/ha-3cp-2workers.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars
# edit REPLACE_* values (tenancy, compartment, region, SSH key, PAR URL, etc.)

cd terraform-stacks/create-cluster
terraform init
terraform apply
```

This provisions VCN/subnets/NSGs, DNS (`api`, `api-int`, `*.apps`), three LBs, IAM dynamic groups/policies, tags, control-plane and compute instances, and CCM/CSI-related outputs.

Key outputs:

| Output | Use |
| --- | --- |
| `dynamic_custom_manifest` | Custom manifests for Assisted Installer (CCM + CSI) |
| `open_shift_api_lb_addr` | Public/external API LB IP |
| `open_shift_apps_lb_addr` | Apps / ingress LB IP |
| `etc_hosts_entry` | Optional local `/etc/hosts` helper |

### 5. Finish installation in Assisted Installer

1. Copy the `dynamic_custom_manifest` output into a file and upload it under the Assisted Installer **Custom manifests** step (folder `manifests`).
2. Assign **Control plane** and **Worker** roles to the discovered hosts.
3. Wait until hosts are Ready, then start installation.
4. After install, download `kubeconfig` and open the OpenShift console.

## Repository layout

```
terraform-stacks/
  create-resource-attribution-tags/   # mandatory tags first
  create-cluster/                     # cluster infra + manifests
  shared_modules/                     # network, lb, compute, iam, dns, manifest, …
examples/
  ha-3cp-2workers.tfvars.example
  resource-attribution-tags.tfvars.example
```

Do not invent alternate CCM/CSI wiring; use the stack manifest output.

## Notes

- Do not change `cluster_name` or `zone_dns` after generating the discovery ISO without regenerating the ISO.
- Ingress LB backend warnings with 2 workers vs 3 routers are expected for this sizing; not a stack bug by default.
- `add-nodes` and autoscaler stacks are intentionally not vendored here; pull them from upstream if needed.
- Never commit real OCIDs, pull secrets, or PAR URLs; keep filled `*.tfvars` / `*.auto.tfvars` out of git.
