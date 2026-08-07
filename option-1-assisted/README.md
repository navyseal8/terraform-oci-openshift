# Option 1 — Oracle/docs Assisted Installer (supported)

Manual Hybrid Cloud Console steps between Terraform applies. This is the path documented by Oracle and Red Hat for OpenShift on OCI.

## Layout

| Path | Role |
| --- | --- |
| [`../terraform-stacks/create-resource-attribution-tags`](../terraform-stacks/create-resource-attribution-tags) | Mandatory tags (once per tenancy) |
| [`../terraform-stacks/create-cluster`](../terraform-stacks/create-cluster) | VCN, LBs, DNS, IAM, instances, CCM/CSI manifest output |
| [`../examples/ha-3cp-2workers.tfvars.example`](../examples/ha-3cp-2workers.tfvars.example) | 3 CP across ADs + 2 workers |

## High-level steps

1. Apply attribution tags  
2. Create cluster in Assisted Installer (platform = Oracle Cloud Infrastructure); match name/domain/CIDRs  
3. Download Minimal discovery ISO → upload to Object Storage → PAR  
4. Apply `create-cluster` with `openshift_image_source_uri` = PAR  
5. Upload `dynamic_custom_manifest` in Assisted Installer  
6. Assign roles → install  

Full detail: [../README.md](../README.md#option-1--oracle-docs-assisted-installer-supported).

For a CLI-only Agent-based path (no Console forms), see [Option 3](../option-3-agent-based/).
