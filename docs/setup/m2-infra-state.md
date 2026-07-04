# M2 Infra State (template)

> Public-safe template. Real values live in the gitignored `m2-infra-state.local.md`.

## Host
- Instance: `<instance-id>` (t4g.medium, Ubuntu 26.04 arm64, ap-southeast-2a)
- Elastic IP: `<eip-public-ip>` (M3 DNS records target this)
- Data volume: `<vol-id>` (20 GB gp3, label `wkx-data`, mounted at `/srv/data`)
- Instance profile: `wkx-host`

## Access
- No SSH. Sessions via `aws ssm start-session --target <instance-id>`.

## M2 status
- M2 completed: `<date>`
- Hands-on artefacts: SSM session connects without SSH; `docker run hello-world` works; `df -h /srv/data` shows the Data volume. Replacement drill passed (ADR 0017).
- Cost note: on-demand spend begins at M2 (about USD $38/mo, roughly NZD $62/mo) until the M10 Savings Plan (about NZD $40/mo).
- Ready for M3: Caddy + TLS.
