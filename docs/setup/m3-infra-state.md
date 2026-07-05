# M3 Infra State (template)

> Public-safe template. Real values live in the gitignored `m3-infra-state.local.md`.

## Images
- ECR: `<PLATFORM_ACCOUNT_ID>.dkr.ecr.ap-southeast-2.amazonaws.com/wkx/caddy:<sha>` (Caddy `<caddy version>`)
- ECR: `<PLATFORM_ACCOUNT_ID>.dkr.ecr.ap-southeast-2.amazonaws.com/wkx/hello:<sha>`

## Network
- Pinned IPv6: `<host-ipv6>` (AAAA target; survives replacement like the EIP)
- DNS: `hello.wingkongexchange.dev` A -> EIP, AAAA -> pinned IPv6, both proxied
- Zone: SSL Full (strict), Always Use HTTPS on, min TLS 1.2

## On-box layout (root volume; re-create after any Host replacement, spec §6 step 4 on)
- Checkout: `/home/platform/wkx-platform`
- Checkout branch: feat/m3-caddy-tls at deploy time; switch to main after the M3 branch merges (git -C /home/platform/wkx-platform checkout main && git pull)
- Snippets: `/etc/caddy/Caddyfile.d/<service>-<env>.caddy` (flat; import glob allows one wildcard)
- Secrets: `/srv/secrets/caddy/prod.env` (600, platform; rendered from SSM)
- Interpolation env: `platform/.env`, `hello/.env` (gitignored; registry + tags + ENV)
- Certificates: `/srv/data/caddy/prod/data` (Data volume; survives replacement)

## M3 status
- M3 completed: `2026-07-05`
- Caddy: v2.11.4 (image wkx/caddy:<sha>)
- Hands-on artefacts: `https://hello.wingkongexchange.dev` 200 with valid TLS; direct EIP curl times out. Origin cert SAN is `*.wingkongexchange.dev`.
- Ready for M4 (observability) and M5 (secrets), in either order.
