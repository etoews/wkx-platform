# infra — Terraform (Layer 1)

Four independent root modules, each with its own state file in one shared S3 bucket:

| Root           | State key                      | Provider creds                       |
|----------------|--------------------------------|--------------------------------------|
| `bootstrap/`   | `bootstrap/terraform.tfstate`  | AWS (SSO, `wkx-platform`)            |
| `aws/`         | `aws/terraform.tfstate`        | AWS (SSO, `wkx-platform`)            |
| `cloudflare/`  | `cloudflare/terraform.tfstate` | `CLOUDFLARE_API_TOKEN`               |
| `mgmt/`        | `mgmt/terraform.tfstate`       | AWS (SSO, `wkx-mgmt`, budgets-only)  |

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

The `mgmt/` root is the cross-account exception: it manages AWS Budgets in the management (payer) account, because only the payer sees consolidated spend. Its provider authenticates as `wkx-mgmt` (a custom budgets-only IdC permission set, not AdministratorAccess) while its backend reaches the shared state bucket in the platform account as `wkx-platform` (the `profile` line in its `backend.local.hcl`). One `aws sso login --profile wkx-mgmt` covers both, they share the same SSO session.

State locking is S3-native (`use_lockfile = true`); there is no DynamoDB table.
