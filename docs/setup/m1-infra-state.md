# M1 Infra State (template)

> Public-safe template. Real values live in the gitignored `m1-infra-state.local.md`.

## Terraform state backend
- State bucket: `wkx-tfstate-<PLATFORM_ACCOUNT_ID>`
- Locking: S3-native (`use_lockfile`), no DynamoDB
- State keys: `bootstrap/`, `aws/`, `cloudflare/`

## Cloudflare
- Apex: `wingkongexchange.dev`
- Zone ID: `<32-char-hex>`
- Nameservers: `<ns1>.ns.cloudflare.com`, `<ns2>.ns.cloudflare.com`
- Caddy DNS-01 token (`wkx-caddy-dns01`): stored in `m1-infra-state.local.md`; moves to SSM in M5

## Outputs (from `terraform output`)
- aws: `vpc_id`, `public_subnet_id`, `web_sg_id`, `host_egress_sg_id`, prefix-list ids

## Security groups
- `web`: ingress 443 only from the Cloudflare IPv4/IPv6 prefix lists. No port 80, no port 22.
- `host-egress`: all outbound.

## M1 status
- M1 completed: 2026-06-21.
- Hands-on artefact: `dig wingkongexchange.dev NS` returns Cloudflare nameservers; `terraform plan` is clean across all three roots from a fresh checkout.
- Manual follow-up: activate cost-allocation tags `Project`, `Env`, `Service` in the Billing console (one-time; `Env`/`Service` activate ahead of the per-service resources that arrive in M6).
- Ready for M2: Graviton host.
