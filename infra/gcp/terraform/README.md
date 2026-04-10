# Terraform — wallet KMS (greenfield)

Creates the same shape as [`../README.md`](../README.md): key ring, symmetric KEK, service account, IAM.

**Project `hyperlinksspacebot` is already provisioned manually.** Use this for a **new** environment or project without importing state.

```bash
cd infra/gcp/terraform
cp terraform.tfvars.example terraform.tfvars   # edit project_id / protection_level
terraform init
terraform plan
terraform apply
```

`prevent_destroy` is set on the crypto key to reduce accidental deletion.

To adopt existing resources instead, use `terraform import` with the resource addresses in `main.tf` (see Terraform docs for `google_kms_*` import IDs).
