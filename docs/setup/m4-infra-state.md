# M4 Infra State (template)

> Public-safe template. Real values live in the gitignored `m4-infra-state.local.md`.

## Log pipeline
- Log groups: `/wkx/hello/prod` (7d), `/wkx/caddy/prod` (30d), `/wkx/platform/prod` (7d)
- Container logs: awslogs driver via `compose.cloud.yml` overlays (ADR 0020); dual logging keeps `docker logs` working
- Access logs: Caddy named logger `wkx` (`http.log.access.wkx`); metric filter `wkx-edge-requests` -> `WKX/Edge` `RequestCount` per Host
- Agent config: SSM `/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG` (String, from `host/cloudwatch-agent.json`); changes re-fetch via SSM RunCommand, no Host replacement

## Alerting
- SNS: `wkx-alerts` (ap-southeast-2); email subscription confirmed `<date>`
- Alarms: `wkx-host-disk-root`, `wkx-host-disk-data`, `wkx-host-mem`, `wkx-host-cpu`, `wkx-host-cpu-credits`
- Billing: `wkx-org-monthly` budget in `infra/mgmt/`; no CloudWatch billing alarm (M4 grill decision)

## Dashboard
- `wkx-prod`: CPU + credit bank, memory, disk, network, request rate (per service + total)

## Host
- Replaced `<date>` for the GPG-verified agent install (ADR 0017); agent version `<version>`
- Primary interface: `<iface>` (pinned in `net.resources`)

## M4 status
- M4 completed: `<date>`
- Hands-on artefacts: Caddy and hello logs tailed in the CloudWatch console; `wkx-host-disk-root` forced to ALARM, email received
- Ready for M5 (secrets + config)
