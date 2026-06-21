# infra — Terraform (Layer 1)

Three independent root modules, each with its own state file in one shared S3 bucket:

| Root           | State key                      | Provider creds            |
|----------------|--------------------------------|---------------------------|
| `bootstrap/`   | `bootstrap/terraform.tfstate`  | AWS (SSO)                 |
| `aws/`         | `aws/terraform.tfstate`        | AWS (SSO)                 |
| `cloudflare/`  | `cloudflare/terraform.tfstate` | `CLOUDFLARE_API_TOKEN`    |

## One-time bootstrap (first run only)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.local.tfvars   # fill in account_id from m0-account-state.local.md
terraform init
terraform apply -var-file=terraform.local.tfvars
# then migrate this root's own state into the bucket it just created:
cp backend.hcl.example backend.local.hcl             # fill in the bucket name from the apply output
terraform init -migrate-state -backend-config=backend.local.hcl
```

## Fresh-checkout setup (any machine, after bootstrap exists)

For each of `aws/` and `cloudflare/`:

```bash
aws sso login                       # AWS_PROFILE=wkx-platform
export CLOUDFLARE_API_TOKEN=...      # for the cloudflare root only
cp backend.hcl.example backend.local.hcl       # fill bucket name
cp terraform.tfvars.example terraform.local.tfvars  # where present; fill from m0-account-state.local.md
terraform init -backend-config=backend.local.hcl
terraform plan -var-file=terraform.local.tfvars
```

State locking is S3-native (`use_lockfile = true`); there is no DynamoDB table.
