# OpenShift on OCI (Terraform)

Two ways to deploy a Red Hat OpenShift Container Platform cluster on Oracle Cloud Infrastructure.

Vendored infra stacks: [oracle-quickstart/oci-openshift](https://github.com/oracle-quickstart/oci-openshift) **v1.6.0** — see [terraform-stacks/VENDOR.md](terraform-stacks/VENDOR.md).

## Choose a path

| | [Option 1 — Assisted (docs)](option-1-assisted/) | [Option 2 — Agent-based CLI](option-2-agent-based/) |
| --- | --- | --- |
| Support posture | Oracle / Red Hat interactive Assisted flow | Oracle Agent-based + Terraform, **CLI only** (no Console forms) |
| Operator UX | Terraform + Hybrid Cloud Console | Four explicit CLI steps |
| ISO | Assisted discovery ISO | `openshift-install agent create image` (local) + PAR |
| Best for | First installs, official guides, RMS | Skipping OCI forms; Agent-based connected installs |
| Product type | Self-managed OCP on your OCI tenancy | Same |

```text
Option 1:  you ↔ Assisted Console ↔ terraform-stacks/create-cluster
Option 2:  tags → phase A → local agent ISO/PAR → phase B → kubeadmin
```

---

## Prerequisites setup

### Install OCI CLI (`oci` binary)

The OCI CLI is Oracle’s command-line tool. You need it for `oci setup config` (credentials) and for Option 2 (Object Storage upload + PAR).

**Linux / macOS (recommended install script):**

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

**Fedora / RHEL:**

```bash
sudo dnf install oci-cli
```

If the package is unavailable on your release, use the install script above.

**pip (any platform):**

```bash
python3 -m pip install --user oci-cli
# ensure ~/.local/bin is on your PATH
```

**Verify:**

```bash
oci --version
```

Official docs: [Installing the CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)

> **Note:** Terraform uses the `oracle/oci` provider and reads `~/.oci/config` for auth — it does not shell out to the `oci` binary. You still want the CLI for credential setup and Option 2 scripts.

### OCI API credentials (Terraform + `oci` CLI)

OCI does not use `access_key_id` / `secret_access_key` like AWS. The equivalent is a config file plus a private key PEM:

| AWS | OCI |
| --- | --- |
| `~/.aws/credentials` | `~/.oci/config` + `~/.oci/oci_api_key.pem` |
| `access_key_id` | `user` (OCID) + `fingerprint` |
| `secret_access_key` | Private key file (`key_file`) |

The vendored stacks use the `oracle/oci` provider with **default auth** — they read `~/.oci/config` automatically. No API keys belong in `.tf` or `.tfvars`.

**One-time setup (recommended):**

```bash
oci setup config
```

This creates:

```text
~/.oci/
  config              # profile, OCIDs, fingerprint, region
  oci_api_key.pem     # private API key (keep secret)
  oci_api_key_public.pem
```

Example `~/.oci/config`:

```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaaxxxxx
fingerprint=aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:00
tenancy=ocid1.tenancy.oc1..aaaaaaaaxxxxx
region=us-ashburn-1
key_file=/home/you/.oci/oci_api_key.pem
```

Restrict the private key:

```bash
chmod 600 ~/.oci/oci_api_key.pem
```

**Verify before `terraform apply`:**

```bash
oci iam region list --output table
# or
oci os ns get
```

Optional explicit provider profile (usually not required):

```hcl
provider "oci" {
  region              = "us-ashburn-1"
  config_file_profile = "DEFAULT"
}
```

Or via environment:

```bash
export OCI_CLI_CONFIG_FILE=$HOME/.oci/config
export OCI_CLI_PROFILE=DEFAULT
```

**Manual API key (Console):** Identity & Security → Users → your user → API Keys → Add API Key. Upload the public key, paste the config preview into `~/.oci/config`, save the private key as `oci_api_key.pem`.

**Credentials vs Terraform variables**

| Location | Contents |
| --- | --- |
| `~/.oci/config` + PEM | Auth only (user, tenancy, fingerprint, key) |
| `terraform.tfvars` | `tenancy_ocid`, `compartment_ocid`, `region` (OCIDs, not secrets) |

Never commit `oci_api_key.pem` or filled `*.tfvars` (see `.gitignore`).

### General requirements (both options)

- `terraform` ≥ 1.0
- OCI tenancy with permissions to create VCN, compute, LB, DNS, IAM, and tags
- Prefer a **multi-AD** region (3 control-plane nodes across ADs)
- Child compartment; Object Storage bucket for ISO images (Option 1 discovery ISO; Option 2 agent ISO)
- Red Hat account and pull secret
- DNS base domain for `zone_dns`
- SSH public key

Option 1 also needs Assisted Installer access. Option 2 also needs `openshift-install` on the machine that builds the agent ISO.

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

See [Prerequisites setup](#prerequisites-setup) for OCI API credentials and shared tooling.

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

## Option 2 — Agent-based CLI (4 steps)

No OCI Console form filling. Same Oracle Agent-based + Terraform sequence as [Oracle docs](https://docs.oracle.com/en-us/iaas/Content/openshift-on-oci/agent-installer-using-stack.htm), driven entirely from the CLI. Agent ISO is **built locally** with `openshift-install`, then uploaded to Object Storage (PAR).

Full walkthrough: [option-2-agent-based/README.md](option-2-agent-based/README.md).

See [Prerequisites setup](#prerequisites-setup) for OCI API credentials (`~/.oci/config`).

```text
1. terraform apply  →  create-resource-attribution-tags
2. terraform apply  →  create-cluster (Agent-based, instances=false)
3. openshift-install agent create image  →  OCI PAR   (script)
4. terraform apply  →  create-cluster (instances=true + PAR)  →  kubeadmin password
```

```bash
# Step 1
cp option-2-agent-based/examples/01-attribution.tfvars.example \
  terraform-stacks/create-resource-attribution-tags/terraform.tfvars
cd terraform-stacks/create-resource-attribution-tags && terraform init && terraform apply

# Step 2
cp option-2-agent-based/examples/02-create-cluster-phase-a.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars
cd ../create-cluster && terraform init && terraform apply

# Step 3 (local ISO + PAR)
export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/../../option-2-agent-based/.work/$CLUSTER_NAME
export OCI_NAMESPACE=... OCI_BUCKET=... OCI_REGION=... OCI_COMPARTMENT_OCID=...
../../option-2-agent-based/scripts/03_create_agent_iso_par.sh

# Step 4 (instances + print kubeadmin)
../../option-2-agent-based/scripts/04_apply_phase_b.sh
# password: option-2-agent-based/.work/$CLUSTER_NAME/auth/kubeadmin-password
```

Requires `openshift-install` on the machine running step 3 (in addition to the tools in Prerequisites setup).

---

## Repository layout

```
option-1-assisted/          # Assisted Installer (docs) path
option-2-agent-based/       # Agent-based 4-step CLI
terraform-stacks/           # vendored Oracle stacks (used by both options)
  create-resource-attribution-tags/
  create-cluster/
  shared_modules/
examples/                   # shared / Option 1 tfvars examples
```

## Notes

- Do not change `cluster_name` or base domain after generating a discovery/agent ISO without regenerating.
- Ingress LB backend warnings with 2 workers are expected for this sizing.
- Never commit real OCIDs, pull secrets, offline tokens, PAR URLs, or kubeadmin passwords.
