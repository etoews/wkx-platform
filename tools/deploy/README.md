# tools/deploy

Turns a sha-addressed Deploy bundle plus an image tag into a verified,
serving Service (design spec §4; ADRs 0006, 0022, 0024). This is the on-box
half of the pipeline: GitHub Actions builds the bundle and calls
`aws ssm send-command`, which runs this script on the Host.

## Deploy

```bash
tools/deploy/deploy.sh --service hello --env prod --tag <sha>
```

All three flags are required; nothing is defaulted (ADR 0006). `--env` is
`prod` or a `pr-<number>` preview env. `--tag` is the image sha, which is also
the bundle's sha, so one commit fully describes a deploy.

The registry (`<account>.dkr.ecr.ap-southeast-2.amazonaws.com`) and the deploy
bucket (`wkx-deploy-<account>`) are derived from the caller's account, so no
account id lives in the script. The Compose interpolation values
(`ECR_REGISTRY`, `<SERVICE>_TAG`, `ENV`) are exported by the script, never
read from a hand-maintained file on the Host.

## What it does, in order

1. Fetch `deploy/<service>/<tag>/bundle.tar.gz` from the deploy bucket and
   unpack it.
2. Refuse the bundle if its `compose.yml` declares no healthcheck: an
   unverifiable Service is not deployed.
3. Render the Env-file from SSM Parameter Store, verbatim
   (`tools/secrets/render-env.sh`).
4. `docker compose -f compose.yml -f compose.cloud.yml -p <service>-<env> up -d`.
5. Render the Caddy snippet to `/etc/caddy/Caddyfile.d/<service>-<env>.caddy`
   (prod is `<service>.wingkongexchange.dev`, every other env is
   `<service>-<env>.wingkongexchange.dev`), recreating the snippet dir if a
   Host replacement removed it, then reload Caddy.
6. Wait for the container to report healthy (bounded), then probe the Service
   hostname through Caddy.

## Fail closed

Every step exits non-zero on failure so the RunCommand and the workflow go
red: a missing bundle, a compose file with no healthcheck, a failed render, an
unhealthy or slow-to-start container, or a failed probe. `--service`, `--env`,
and `--tag` are shape-validated to block traversal before they reach a path or
an S3 key.

## Tests

```bash
tools/deploy/test.sh    # stubs aws, docker, and curl; no AWS or network needed
shellcheck tools/deploy/deploy.sh tools/deploy/test.sh
```
