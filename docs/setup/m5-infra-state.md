# M5 infra state: secrets + config

Public-safe template. Real identifiers live in `m5-infra-state.local.md`
(gitignored, never committed).

## What M5 changed
- Host replaced (cloud-init change, ADR 0017): instance `<NEW_INSTANCE_ID>`.
- IMDS hop limit 1 (ADR 0023): containers cannot reach instance credentials.
- `/srv/secrets` created by cloud-init (0700, platform).
- Env-file render: `tools/secrets/render-env.sh` (ADR 0022); Compose
  consumes with `env_file` long syntax (`format: raw`, `required: true`).

## Parameters (names only; values never recorded here)
- `/wkx/caddy/prod/CLOUDFLARE_API_TOKEN` (SecureString, Terraform-managed)
- `/wkx/hello/prod/MESSAGE` (String, operator-set)
- CloudWatch agent config parameter (M4)

## Replacement runbook additions (after any Host replacement)
1. Checkout + interpolated env-files: per m3/m4 local state docs.
2. Render Env-files before starting stacks:
   `tools/secrets/render-env.sh --service caddy --env prod`
   `tools/secrets/render-env.sh --service hello --env prod`
3. Start stacks (compose file headers). Expect `wkx-host-cpu-credits`
   in ALARM 5 to 6 hours while the credit bank refills.

## M5 status
- M5 completed: `2026-07-10`
- Hands-on artefacts: page served SSM MESSAGE; Parameter update flowed
  to the page via re-render + up; render posture 600/700 verified.
