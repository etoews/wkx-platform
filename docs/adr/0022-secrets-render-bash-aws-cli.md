# Secrets render to Env-files via bash and the AWS CLI, not a Python helper

Status: accepted

At deploy time a small committed script, `tools/secrets/render-env.sh`, reads a Service's Parameter namespace (`/wkx/<service>/<env>/`) with `aws ssm get-parameters-by-path` and renders the Env-file at `/srv/secrets/<service>/<env>.env` (0600, atomic write, fail closed on any key or value the env-file format cannot represent). The design spec and roadmap originally promised a uv-packaged Python helper under `tools/secrets/`; M5 amended that. The job is one small transform, and the Python shape would have cost a pinned uv install in cloud-init, a PyPI dependency in the deploy path, and permanent dev-to-box interpreter drift, machinery disproportionate to the work.

Env-files live on the disposable root volume, never the Data volume: M10 snapshots the Data volume, and rendered secrets must not outlive the box inside EBS snapshots. `/srv/secrets` itself is created by cloud-init, because the `platform` user cannot create directories under root-owned `/srv`, so a Host replacement reconstructs the full render path without manual steps.

Python under `tools/` remains the standard for any tool that genuinely outgrows bash (the M8 scaffold is the likely first case): uv-packaged with ruff, pytest, and ty. The revisit trigger is a tool outgrowing bash, not a preference for Python.

_Source: M5 design spec (2026-07-10) §2, §3._
