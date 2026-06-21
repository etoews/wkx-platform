# M1 Infra State (template)

> Public-safe template. Real values live in the gitignored `m1-infra-state.local.md`.

## Terraform state backend
- State bucket: `wkx-tfstate-<PLATFORM_ACCOUNT_ID>`
- Locking: S3-native (`use_lockfile`), no DynamoDB
- State keys: `bootstrap/`, `aws/`, `cloudflare/`

## Cloudflare
- Apex: `wkx.dev`
- Zone ID: `<32-char-hex>`
- Nameservers: `<ns1>.ns.cloudflare.com`, `<ns2>.ns.cloudflare.com`
- Caddy DNS-01 token (`wkx-caddy-dns01`): stored in `m1-infra-state.local.md`; moves to SSM in M5

## Outputs (from `terraform output`)
- aws: `vpc_id`, `public_subnet_id`, `web_sg_id`, `host_egress_sg_id`, prefix-list ids
