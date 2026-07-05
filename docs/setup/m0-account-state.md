# M0 Account State (template)

> Immutable identifiers established during M0. Used by M1 Terraform.
>
> **This file is a public-safe template.** When you complete M0 yourself, copy this file to `m0-account-state.local.md` (gitignored) and fill in the real values there. The committed copy keeps placeholders so the repo can stay public without leaking account state.

## Email aliases

- Management account root: `<management-account-email>`
- Platform account root: `<platform-account-email>`

## AWS account IDs

- Management account: `<MGMT_ACCOUNT_ID>` (12 digits)
- Platform account: `<PLATFORM_ACCOUNT_ID>` (12 digits)

## IAM Identity Center

- IdC instance ARN: `arn:aws:sso:::instance/ssoins-<INSTANCE_ID>`
- IdC region: `ap-southeast-2`
- SSO start URL: `https://<your-idc-subdomain>.awsapps.com/start`
- IdC username: `<your-idc-username>`
- Permission set name: `AdministratorAccess` (AWS-managed predefined set; assigned on the platform account)
- Permission set name: `wkx-budgets` (custom, budgets-only; assigned on the management account so `infra/mgmt/` can manage budgets without AdministratorAccess there)

## Cloudflare

- Account email: `<your-cloudflare-email>`
- Account ID: `<32-char-hex>`

## Local tool versions

Recorded at M0 completion. Replace with output of each `--version` command:

```
mise --version                   → ...
docker --version                 → ...
docker compose version           → ...
gh --version                     → ...
aws --version                    → ...
session-manager-plugin --version → ...
terraform --version              → ...
uv --version                     → ...
```

Notes:
- `terraform` installed via `hashicorp/tap/terraform` (Homebrew), not mise.
- `session-manager-plugin` installed from the AWS-signed `mac_arm64` bundle (the Homebrew cask is deprecated 2026-09-01).

## M0 status

- M0 completed: `<YYYY-MM-DD>`
- All four hands-on verifications passed.
- Ready for M1.
