# Option 2 — ROSA-like facade (ARCHIVED)

> **Archived.** Prefer [Option 1 (Assisted)](../../option-1-assisted/) or [Option 2 (Agent-based CLI)](../../option-2-agent-based/).

Single `terraform apply` / `./deploy.sh` that orchestrates the full OpenShift-on-OCI Assisted Installer flow so you do not click through the Hybrid Cloud Console between steps.

**Still self-managed OCP on your OCI account** (not a managed ROSA service). Internally it uses the same Oracle `create-cluster` stack as Option 1.

## What it automates

```text
Assisted API register (platform=oci)
  → download minimal discovery ISO
  → upload to Object Storage + PAR
  → terraform apply create-cluster (3 CP / N workers)
  → upload dynamic_custom_manifest (CCM/CSI)
  → assign master/worker roles
  → start install → wait → kubeconfig
```

## Prerequisites

| Tool / secret | Purpose |
| --- | --- |
| `terraform` ≥ 1.0 | Root module + nested create-cluster apply |
| `oci` CLI configured | Bucket, object put, PAR |
| `curl`, `jq`, `bash` | Assisted Installer API |
| Red Hat **pull secret** | Cluster registration |
| Red Hat **offline token** | API access ([console token page](https://console.redhat.com/openshift/token)) |
| OCI tenancy / compartment / multi-AD region | Infra |
| Object Storage namespace + bucket name | ISO hosting |

## Quick start

```bash
cd archive/option-2-rosa-like
cp terraform.tfvars.example terraform.tfvars
# edit secrets and OCIDs

chmod +x deploy.sh scripts/*.sh
./deploy.sh
# or: terraform init && terraform apply
```

Outputs:

- `kubeconfig_path` / `kubeconfig`
- `assisted_state` (cluster_id, infra_env_id, …)
- `cluster_console_hint`

Working files land under `.work/<cluster_name>/` (gitignored): ISO, PAR URL, tfstate for nested stacks, manifests, kubeconfig.

## Defaults (same as Option 1 example)

- 3 control plane (spread across ADs), 2 workers
- Machine `10.0.0.0/16`, pods `10.128.0.0/14`, services `172.30.0.0/16`

## Destroy

```bash
WORK_DIR=.work/<cluster_name> \
  RH_OFFLINE_TOKEN=... \
  ./scripts/99_destroy.sh
```

This destroys the nested `create-cluster` state and deregisters the Assisted cluster. Attribution tags are left in place unless `DESTROY_ATTRIBUTION_TAGS=true`.

Root-module `terraform destroy` only removes null_resource tracking; always run `99_destroy.sh` for real cleanup.

## Limitations vs ROSA

- Runs on the machine executing Terraform (local-exec); needs network to `api.openshift.com` and OCI.
- Install wait can take 1–2+ hours; timeouts are configurable.
- Host role assignment is first N hosts → master, rest → worker (by hostname sort).
- Not a Red Hat managed service; you own upgrades, SLAs, and OCI cost.

## Relation to primary options

See Option 1 (Assisted) and Option 2 (Agent-based CLI) in the repository root README.
