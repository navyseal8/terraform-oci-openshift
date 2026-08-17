# Option 2 — Agent-based Installer (Terraform CLI, 4 steps)

Skip the OCI Console / Resource Manager forms. Drive the same vendored [`create-cluster`](../terraform-stacks/create-cluster) stack from the CLI, then build the agent ISO **locally** with `openshift-install`, upload a PAR, and apply phase B.

Aligned with Oracle: [Installing a Cluster with Agent-based Installer Using Terraform](https://docs.oracle.com/en-us/iaas/Content/openshift-on-oci/agent-installer-using-stack.htm).

```text
Step 1  attribution tags
Step 2  create-cluster phase A  (Agent-based, create_openshift_instances=false)
Step 3  openshift-install agent create image  →  OCI Object Storage PAR   (local build)
Step 4  create-cluster phase B  (instances=true + PAR)  →  share kubeadmin password
```

## Prerequisites

| Requirement | Notes |
| --- | --- |
| `terraform` ≥ 1.0 | Attribution + create-cluster |
| OCI API credentials | Same as any stack apply (`~/.oci/config` or env) |
| `oci` CLI | Step 3 upload + PAR |
| `openshift-install` | Matching your OCP version; on `PATH` or set `OPENSHIFT_INSTALL` |
| Red Hat pull secret | Embedded in phase A/B `redhat_pull_secret` |
| Multi-AD region (preferred) | 3 control-plane nodes across ADs |
| Object Storage namespace + bucket name | ISO hosting |

Connected install only (`is_disconnected_installation = false`). Disconnected/webserver ABI is out of scope here.

## Defaults

| Setting | Value |
| --- | --- |
| Control plane | 3 (spread across ADs/FDs) |
| Workers | 2 |
| `rendezvous_ip` | `10.0.16.20` (inside `10.0.16.0/20`) |
| Machine / VCN | `10.0.0.0/16` |
| Pod network | `10.128.0.0/14` |
| Service network | `172.30.0.0/16` |

Keep `cluster_name`, `zone_dns`, `rendezvous_ip`, and node counts identical across steps 2–4 and the agent ISO.

---

## Step 1 — Resource attribution tags

Once per tenancy (skip if `openshift-tags` already exists).

```bash
cp option-2-agent-based/examples/01-attribution.tfvars.example \
  terraform-stacks/create-resource-attribution-tags/terraform.tfvars
# edit REPLACE_*

cd terraform-stacks/create-resource-attribution-tags
terraform init
terraform apply
```

Reuse that compartment OCID as `tag_namespace_compartment_ocid_resource_tagging` in steps 2 and 4.

---

## Step 2 — Create cluster phase A (no instances)

```bash
cp option-2-agent-based/examples/02-create-cluster-phase-a.tfvars.example \
  terraform-stacks/create-cluster/terraform.tfvars
# edit REPLACE_* (pull secret, SSH key, OCIDs, region, domain)
# public_ssh_key must be the full OpenSSH *public* key (ssh-ed25519 ... or ssh-rsa ...), not the private key

cd terraform-stacks/create-cluster
terraform init
terraform apply
```

Important variables:

- `installation_method = "Agent-based"`
- `create_openshift_instances = false`

Capture outputs into a work directory (used by step 3):

```bash
export CLUSTER_NAME=ocidemo   # must match cluster_name
export WORK_DIR=$PWD/../../option-2-agent-based/.work/$CLUSTER_NAME
mkdir -p "$WORK_DIR/openshift"

terraform output -raw agent_config > "$WORK_DIR/agent-config.yaml"
terraform output -raw install_config > "$WORK_DIR/install-config.yaml"
terraform output -raw dynamic_custom_manifest \
  > "$WORK_DIR/openshift/oci-dynamic-custom-manifest.yaml"
```

(Or let `scripts/03_create_agent_iso_par.sh` read outputs directly from this stack directory.)

---

## Step 3 — Create agent ISO (local) and Object Storage PAR

Build happens on the machine running the script (not an OCI builder VM).

```bash
cd <repo-root>
chmod +x option-2-agent-based/scripts/*.sh

export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export OCI_NAMESPACE=REPLACE_NAMESPACE
export OCI_BUCKET=openshift-agent-iso
export OCI_REGION=us-ashburn-1
export OCI_COMPARTMENT_OCID=ocid1.compartment...
# optional: export OPENSHIFT_INSTALL=/path/to/openshift-install

./option-2-agent-based/scripts/03_create_agent_iso_par.sh
```

The script:

1. Ensures `agent-config.yaml`, `install-config.yaml`, and `openshift/oci-dynamic-custom-manifest.yaml` exist (from Terraform outputs if missing)
2. Runs `openshift-install agent create image --dir "$WORK_DIR"`
3. Uploads the ISO and creates an ObjectRead PAR
4. Writes `$WORK_DIR/iso-par-url.txt`
5. Leaves `$WORK_DIR/auth/kubeadmin-password` and `$WORK_DIR/auth/kubeconfig`

---

## Step 4 — Install cluster (phase B) and share kubeadmin password

```bash
export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME

# Uses terraform-stacks/create-cluster/terraform.tfvars (from step 2),
# sets create_openshift_instances=true and openshift_image_source_uri=<PAR>
./option-2-agent-based/scripts/04_apply_phase_b.sh
```

Or apply manually with [examples/04-create-cluster-phase-b.tfvars.example](examples/04-create-cluster-phase-b.tfvars.example) after pasting the PAR URL.

After apply, instances boot from the agent ISO and installation proceeds (rendezvous node at `rendezvous_ip`). Monitor if needed:

```bash
ssh -i <key> core@10.0.16.20   # via bastion / VPN as appropriate
journalctl -f
```

### Kubeadmin password

Printed by `04_apply_phase_b.sh` and stored at:

```text
option-2-agent-based/.work/<cluster>/auth/kubeadmin-password
option-2-agent-based/.work/<cluster>/auth/kubeconfig
```

```bash
export KUBECONFIG=option-2-agent-based/.work/$CLUSTER_NAME/auth/kubeconfig
oc get nodes
oc get clusteroperators
```

Console (once DNS or `/etc/hosts` from stack output `etc_hosts_entry` is set):

```text
https://console-openshift-console.apps.<cluster_name>.<zone_dns>
```

User: `kubeadmin` — password from the file above.

---

## Layout

```
option-2-agent-based/
  README.md
  examples/
    01-attribution.tfvars.example
    02-create-cluster-phase-a.tfvars.example
    04-create-cluster-phase-b.tfvars.example
  scripts/
    03_create_agent_iso_par.sh
    04_apply_phase_b.sh
  .work/                         # gitignored
```

## Notes

- Do not change cluster name, base domain, rendezvous IP, or node counts after generating the agent ISO.
- Phase A and phase B use the same Terraform state in `terraform-stacks/create-cluster` (normal second apply).
- Never commit pull secrets, PAR URLs, or `auth/kubeadmin-password`.
