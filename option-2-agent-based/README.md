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

If you change `public_ssh_key` (or other values that affect `install_config`) after phase A, run `terraform apply` again so outputs in state are refreshed — `terraform output` alone reads the last applied state. Then delete the cached workdir file and regenerate:

```bash
rm -f "$WORK_DIR/install-config.yaml"
terraform output -raw install_config > "$WORK_DIR/install-config.yaml"
```

The `sshKey` line must start with `ssh-ed25519` or `ssh-rsa` (use `cat ~/.ssh/id_ed25519.pub`, not the private key).

---

## Step 3 — Create agent ISO (local) and Object Storage PAR

Build happens on the machine running the script (not an OCI builder VM).

### Object Storage variables

| Variable | What it is | Example |
| --- | --- | --- |
| `OCI_NAMESPACE` | Tenancy Object Storage namespace (fixed per account) | `axaamtblrmyj` |
| `OCI_BUCKET` | Bucket name you choose | `openshift-agent-iso` |
| `OCI_REGION` | Region where the bucket lives | `ap-singapore-1` |
| `OCI_COMPARTMENT_OCID` | Compartment that owns the bucket | `ocid1.compartment...` |

`OCI_NAMESPACE` is **not** your org name or bucket name. Look it up:

```bash
oci os ns get --query 'data' --raw-output
```

```bash
cd <repo-root>
chmod +x option-2-agent-based/scripts/*.sh

export CLUSTER_NAME=ocidemo
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export OCI_NAMESPACE=REPLACE_NAMESPACE   # from: oci os ns get
export OCI_BUCKET=openshift-agent-iso      # any name you choose
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

### If step 3 fails partway (ISO built, no `iso-par-url.txt`)

Uploading the ISO does **not** create a PAR. If the script failed during bucket upload or PAR creation, `$WORK_DIR/iso-par-url.txt` will be missing and `oci os preauth-request list` may return nothing — that is expected.

Finish upload + PAR from the CLI (skip ISO rebuild if `agent.x86_64.iso` already exists):

```bash
export WORK_DIR=$PWD/option-2-agent-based/.work/$CLUSTER_NAME
export OCI_NAMESPACE=REPLACE_NAMESPACE
export OCI_BUCKET=openshift-agent-iso
export OCI_REGION=ap-singapore-1
export OCI_COMPARTMENT_OCID=ocid1.compartment...
export OBJECT_NAME=${CLUSTER_NAME}-agent.iso
export PAR_NAME=${CLUSTER_NAME}-agent-par
export PAR_EXPIRE_DAYS=7

# Confirm the ISO is present locally
ls -lh "$WORK_DIR"/agent*.iso

# Confirm the object in Object Storage (or note the actual object name)
oci os object list \
  --namespace-name "$OCI_NAMESPACE" \
  --bucket-name "$OCI_BUCKET" \
  --region "$OCI_REGION" \
  --all

# Create bucket if needed, then upload
oci os bucket get --namespace-name "$OCI_NAMESPACE" --bucket-name "$OCI_BUCKET" --region "$OCI_REGION" \
  || oci os bucket create \
       --namespace-name "$OCI_NAMESPACE" \
       --compartment-id "$OCI_COMPARTMENT_OCID" \
       --name "$OCI_BUCKET" \
       --region "$OCI_REGION"

oci os object put \
  --namespace-name "$OCI_NAMESPACE" \
  --bucket-name "$OCI_BUCKET" \
  --name "$OBJECT_NAME" \
  --file "$WORK_DIR/agent.x86_64.iso" \
  --region "$OCI_REGION" \
  --force

# Create PAR (full URL is only returned at create time)
expire=$(date -u -d "+${PAR_EXPIRE_DAYS} days" +%Y-%m-%dT%H:%M:%SZ)

par_json=$(oci os preauth-request create \
  --namespace-name "$OCI_NAMESPACE" \
  --bucket-name "$OCI_BUCKET" \
  --name "$PAR_NAME" \
  --access-type ObjectRead \
  --time-expires "$expire" \
  --object-name "$OBJECT_NAME" \
  --region "$OCI_REGION")

access_uri=$(echo "$par_json" | jq -r '.data."access-uri"')
if [[ "$access_uri" == http* ]]; then
  par_url="$access_uri"
else
  par_url="https://objectstorage.${OCI_REGION}.oraclecloud.com${access_uri}"
fi

echo "$par_url" | tee "$WORK_DIR/iso-par-url.txt"
```

`preauth-request list` shows PAR metadata only, not the URL. Save `iso-par-url.txt` for step 4 (`openshift_image_source_uri`).

### Re-running step 3 after a successful ISO build

`openshift-install` stores state under `$WORK_DIR` (`.openshift_install_state.json`) and removes `install-config.yaml`, `agent-config.yaml`, and `openshift/` after the first successful build. **Re-running the full script in the same directory often fails** with a generic configuration error.

If `agent.x86_64.iso` already exists, skip the rebuild and upload only:

```bash
export SKIP_ISO_BUILD=1
./option-2-agent-based/scripts/03_create_agent_iso_par.sh
```

For a clean ISO rebuild (e.g. after changing cluster config), reset the workdir install state first:

```bash
rm -f "$WORK_DIR/.openshift_install_state.json" "$WORK_DIR/.openshift_install.log"
cp -f "$WORK_DIR/agent-config.yaml.bak" "$WORK_DIR/agent-config.yaml"
cp -f "$WORK_DIR/install-config.yaml.bak" "$WORK_DIR/install-config.yaml"
mkdir -p "$WORK_DIR/openshift"
terraform -chdir=terraform-stacks/create-cluster output -raw dynamic_custom_manifest \
  > "$WORK_DIR/openshift/oci-dynamic-custom-manifest.yaml"
unset SKIP_ISO_BUILD
./option-2-agent-based/scripts/03_create_agent_iso_par.sh
```

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
