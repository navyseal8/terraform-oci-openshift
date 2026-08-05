# OpenShift on OCI (Terraform)

Two ways to deploy a Red Hat OpenShift Container Platform cluster on Oracle Cloud Infrastructure.

Vendored infra stacks: [oracle-quickstart/oci-openshift](https://github.com/oracle-quickstart/oci-openshift) **v1.6.0** — see [terraform-stacks/VENDOR.md](terraform-stacks/VENDOR.md).

## Choose a path

| | [Option 1 — Assisted (docs)](option-1-assisted/) | [Option 2 — ROSA-like facade](option-2-rosa-like/) |
| --- | --- | --- |
| Support posture | Oracle / Red Hat documented interactive flow | Community automation around the same stacks + Assisted **API** |
| Operator UX | Terraform + Hybrid Cloud Console steps | Single `terraform apply` / `./deploy.sh` |
| Best for | First installs, RMS console, following official guides | CI / repeatable labs closer to ROSA Terraform UX |
| Product type | Self-managed OCP on your OCI tenancy | Same (not managed ROSA) |

```text
Option 1:  you  ↔ Assisted Console  ↔  terraform-stacks/create-cluster
Option 2:  terraform apply  →  scripts drive Assisted API + create-cluster + install
```

---

## Option 1 — Oracle/docs Assisted Installer (supported)

Manual steps between applies. See also [option-1-assisted/README.md](option-1-assisted/README.md).

### Target topology

| Role | Count | Placement |
| --- | --- | --- |
| Control plane | 3 | Round-robin across Availability Domains |
| Workers (compute) | 2 | Spread across ADs / FDs |

Cloud provider integrations (via stack IAM + `dynamic_custom_manifest`):

- **Load balancers** — OCI flexible LBs for `api`, `api-int`, and `*.apps` (CCM)
- **Storage** — OCI Block Volumes (CSI)
- **Identity** — Instance Principals (dynamic groups + policies)

Example inputs: [examples/ha-3cp-2workers.tfvars.example](examples/ha-3cp-2workers.tfvars.example).

### Network CIDRs

| Network | Terraform variable | CIDR |
| --- | --- | --- |
| Machine / VCN | `vcn_cidr` | `10.0.0.0/16` |
| Public subnet | `public_cidr` | `10.0.0.0/20` |
| Private OCP subnet | `private_cidr_ocp` | `10.0.16.0/20` |
| Private BM subnet | `private_cidr_bare_metal` | `10.0.32.0/20` |
| **Pod / clusterNetwork** | `cluster_network_cidr_block` | **`10.128.0.0/14`** |
| **Service network** | `service_network_cidr_block` | **`172.30.0.0/16`** |

Use the **same** values in Assisted Installer networking.

### Prerequisites

- OCI tenancy with permissions to create VCN, compute, LB, DNS, IAM, and tags
- Prefer a **multi-AD** region
- Child compartment and Object Storage bucket for the discovery ISO
- Red Hat account, pull secret, Assisted Installer access
- DNS base domain for `zone_dns`
- SSH public key

### Apply order

#### 1. Resource attribution tags (once per tenancy)

```bash
cp examples/resource-attribution-tags.tfvars.example \
  terraform-stacks/create-resource-attribution-tags/terraform.tfvars
# edit REPLACE_* values

cd terraform-stacks/create-resource-attribution-tags
terraform init
terraform apply
```

#### 2. Assisted Installer (Red Hat Hybrid Cloud Console)

1. Create a cluster with partner platform **Oracle Cloud Infrastructure**.
2. Set **Cluster name** = Terraform `cluster_name` and **Base domain** = Terraform `zone_dns`.
3. Set Machine / Cluster (pod) / Service CIDRs to match the table above.
4. Generate the **Minimal** discovery ISO.

Docs: [Installing on Oracle Distributed Cloud with Assisted Installer](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_oracle_distributed_cloud/installing-oci-assisted-installer).

#### 3. Upload ISO and create a PAR

Upload the ISO to Object Storage, create a Pre-Authenticated Request, set `openshift_image_source_uri`.

#### 4. Create cluster infrastructure

```bash
cp examples/ha-3cp-2workers.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars
# edit REPLACE_* values

cd terraform-stacks/create-cluster
terraform init
terraform apply
```

Key outputs: `dynamic_custom_manifest`, API/apps LB addresses, `etc_hosts_entry`.

#### 5. Finish installation in Assisted Installer

Upload manifests, assign Control plane / Worker roles, install, download `kubeconfig`.

---

## Option 2 — ROSA-like facade (improved)

Automates Assisted Installer API + ISO/PAR + `create-cluster` + role assignment + install wait.

```bash
cd option-2-rosa-like
cp terraform.tfvars.example terraform.tfvars
# fill pull_secret, rh_offline_token, OCIDs, bucket namespace, SSH key

chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

Details, destroy helper, and limitations: [option-2-rosa-like/README.md](option-2-rosa-like/README.md).

Requires `oci` CLI, `curl`, `jq`, Red Hat offline token, and network access to `api.openshift.com`.

---

## Repository layout

```
option-1-assisted/          # docs pointer to supported path
option-2-rosa-like/         # ROSA-like root module + scripts
terraform-stacks/           # vendored Oracle stacks (used by both options)
  create-resource-attribution-tags/
  create-cluster/
  shared_modules/
examples/                   # Option 1 tfvars examples
```

## Notes

- Do not change `cluster_name` or base domain after generating the discovery ISO without regenerating.
- Ingress LB backend warnings with 2 workers are expected for this sizing.
- Never commit real OCIDs, pull secrets, offline tokens, or PAR URLs.
