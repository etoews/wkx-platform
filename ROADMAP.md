# WKX Platform — Roadmap

Build order, deliverables, and hands-on artefact at every milestone.

For the full design rationale, see [docs/superpowers/specs/2026-05-01-wkx-platform-design.md](docs/superpowers/specs/2026-05-01-wkx-platform-design.md).

**Sizes:** S = ≤ a session · M = a focused weekend or 2 evenings · L = several sessions, expect debugging.

**Critical path:** M0 → M1 → M2 → M3 is sequential. M4/M5 can run in parallel after M3. M7–M10 are independently orderable. M11 is opt-in.

---

## M0 · Prerequisites — Size: S

**Deliverables**
- Fresh AWS management account (new email alias, e.g. `you+aws-mgmt@example.com`).
- AWS Organisations enabled on the management account.
- Platform member account created (email alias `you+aws-platform@example.com`).
- IAM Identity Center on the mgmt account; SSO permission set granting access to the platform account.
- Cloudflare account exists. (Zone-scoped API token is created in M1 after the zone exists; M0 just needs login access.)
- Local tools installed: Terraform, Docker Desktop, mise/uv, GitHub CLI.

**Hands-on artefact**
- Log in to the platform account via IAM Identity Center SSO.
- `terraform version`, `docker version`, `aws sts get-caller-identity` all return successfully.

**Notes**
- `<APP_DOMAIN>` (Mode-1 per-app domains) remains a placeholder through M10. `wkx.dev` is registered in M1.

---

## M1 · Networking + DNS skeleton — Size: M

**Deliverables**
- Terraform state backend in the platform account: S3 bucket (versioned, encrypted) with S3-native state locking (`use_lockfile`). No DynamoDB lock table (see the M1 plan for rationale).
- VPC with one public subnet, IGW, default route, IPv6 enabled.
- Security groups:
  - `web` — allows 80/443 from Cloudflare IPv4 + IPv6 ranges (via Terraform data source pulling Cloudflare's published list).
  - `host-egress` — allows all outbound.
  - **No port 22 open.**
- Cloudflare zone for `wkx.dev`.
- All per-project Terraform modules **require** an `env` input — no default. Account-level/host-level resources don't use the env dimension.
- **AWS resource tagging strategy.** Standardised tags applied to every Terraform-managed AWS resource via the AWS provider's `default_tags` block. Required tag keys:
  - `Project` = `wkx` (always)
  - `ManagedBy` = `terraform` (always)
  - `Env` = `<env>` (where the resource has an env dimension; omitted for host/account-level)
  - `Service` = `<service>` (where the resource is per-service; omitted for shared/platform)
  - `Repo` = `wkx-platform` or `wkx-<project>` (the GitHub repo that owns this resource's code)
  Activate cost allocation tags in the Billing console for `Project`, `Env`, `Service` so per-env / per-service spend is queryable.

**Hands-on artifact**
- `dig wkx.dev NS` returns Cloudflare nameservers.
- `terraform plan` runs clean from a fresh checkout.

---

## M2 · Graviton host — Size: M

**Deliverables**
- EC2 t4g.medium in the public subnet, ARM64 Ubuntu 24.04 AMI.
- Elastic IP attached.
- IAM instance profile granting:
  - SSM Session Manager + RunCommand
  - ECR pull
  - CloudWatch Logs/Metrics write
  - SSM Parameter Store read by `/wkx/*` path (broad scope; service-first paths make per-service IAM the natural granularity, deferred to the M2 plan)
  - S3 write to the backups bucket
- cloud-init user-data (`host/cloud-init.yaml`) installs:
  - Docker + Compose plugin
  - SSM agent (usually preinstalled), CloudWatch agent
  - Mounts EBS gp3 to `/srv/data` (per-service subdirs created at deploy time)
  - Creates `platform` user

**Hands-on artifact**
- `aws ssm start-session --target <instance-id>` connects without SSH.
- On the box: `docker run hello-world` works; `df -h /srv/data` shows the mounted volume.

---

## M3 · Caddy + TLS — Size: L

**Deliverables**
- `platform/compose.yml` deployed to the box. Caddy image is custom-built via `xcaddy` with the `caddy-dns/cloudflare` plugin (small Dockerfile in `platform/caddy/`, image pushed to ECR).
- Caddy obtains wildcard cert for `*.wkx.dev` via DNS-01 using the Cloudflare API token (stored in SSM, fetched at deploy).
- Caddy config: top-level `Caddyfile` does `import /etc/caddy/Caddyfile.d/*/<env>.caddy`.
- "hello" smoke-test app deployed as a Compose service (initially in the platform repo; extracted to its own repo at M6).
- Cloudflare DNS A + AAAA records for `hello.wkx.dev` pointing at the EIP, proxy mode ON.
- Origin SG hardened to Cloudflare IP ranges only.

**Hands-on artifact**
- `https://hello.wkx.dev` returns 200 with valid TLS in a browser.
- `curl -sI` against the EIP directly is blocked (proves SG works).

---

## M4 · Observability — Size: M

**Deliverables**
- CloudWatch agent config ships:
  - syslog → `/wkx/system/<env>`
  - Docker container logs (JSON file driver) → `/wkx/<service>/<env>`
  - host metrics: CPU, memory, disk, network
- One log group per service, created by Terraform.
- CloudWatch dashboard: CPU, memory, disk, network, request rate (from Caddy access logs).
- Billing alarm at 80% of NZD $50 (≈ USD $24).

**Hands-on artifact**
- Tail Caddy and hello logs in the CloudWatch console.
- Force the billing alarm in test mode → email arrives at the configured address.

---

## M5 · Secrets + config — Size: M

**Deliverables**
- SSM Parameter Store namespace `/wkx/<service>/<env>/<KEY>`.
- Python helper (`tools/secrets/`, packaged with uv) that reads parameters by path and renders a `.env` file at deploy time.
- Compose env-file path standardized at `/srv/secrets/<service>/<env>.env` (gitignored, regenerated on deploy).
- Instance role permits read-by-path; deploy script (M6) re-renders before `compose up`.

**Hands-on artifact**
- Set `/wkx/hello/prod/MESSAGE = "hello world"`.
- Run deploy → page shows the message.
- Update parameter, redeploy → page shows new message.

---

## M6 · CI/CD — Size: L

**Deliverables**
- Terraform module `ecr-repo` creates an ECR repo + the IAM role/trust for OIDC GHA push, scoped per project. Includes lifecycle policy: expire `prod` tags after 30 days, expire branch tags after 14 days. Older rollbacks rebuild from git.
- GitHub OIDC provider configured in the platform account.
- GHA workflow template:
  - Build multi-stage container (`Dockerfile` targets `linux/arm64` by default).
  - Push to ECR with tag `<sha>`.
  - Trigger deploy via `aws ssm send-command` invoking a script that:
    - Renders env-file from SSM (using the M5 helper).
    - Pulls image, runs `docker compose -p <service>-<env> up -d`.
    - Drops the project's caddy snippet at `/etc/caddy/Caddyfile.d/<service>/<env>.caddy`.
    - Reloads Caddy.
- Extract "hello" to its own repo `wkx-hello` and wire it through the new pipeline.
- Deploy script (`tools/deploy/`) **requires** `--env` — no default. Forgetting it errors out with valid env patterns. CI workflows hardcode their target env (PR-open: `pr-<N>`; main-merge: `prod`).

**Hands-on artifact**
- Push to `wkx-hello` main → deployed in under 2 minutes.
- Roll back via `git revert` → previous version live.

---

## M7 · Auto-upgrades — Size: M

**Deliverables**
- Renovate enabled (GitHub-hosted free tier). Configurations cover:
  - App deps (uv lock files)
  - Dockerfile base images
  - Compose images
  - Terraform providers
  - GitHub Actions versions
- `renovate.json` policy:
  - Auto-merge minor + patch when CI is green.
  - Major versions stay manual.
- Ubuntu unattended-upgrades enabled on the box for security patches.

**Hands-on artifact**
- First Renovate auto-PR appears in some repo, CI passes, it auto-merges.
- `unattended-upgrade --dry-run` on the box shows expected behavior.

---

## M8 · "Add a project" workflow — Size: L

**Deliverables**
- Reference project at `wkx-platform/template/` — a real, CI-tested working app (the `hello` smoke-test app from M3 doubles as the canonical reference). Contains:
  - `Dockerfile` (multi-stage, ARM64; flag for amd64 opt-in)
  - `compose.yml` (service + named volume + `mem_limit` + `cpus`)
  - `caddy.snippet` (env-templated host block)
  - `.github/workflows/deploy.yml`
  - `renovate.json`
  - `.devcontainer/`
  - `README.md` with deploy instructions
- `wkx-scaffold` CLI in `tools/scaffold/` (Python, packaged with uv). Behaviour:
  1. Clone `wkx-platform/template/` into a new working directory `wkx-<name>/`.
  2. Substitute `<name>`, `<port>`, `<hostname>` (and a few other placeholders) across all files via plain string replace.
  3. `git init`, initial commit.
  4. `gh repo create wkx-<name> --private --push`.
  5. Open a PR against `wkx-platform` adding `infra/projects/<name>.tf` (uses the M6 `ecr-repo` module).
- Platform contract documented in `wkx-platform/CLAUDE.md` so AI agents can extend new projects in a conformant way.
- Demo: scaffold and deploy a SQLite-backed "notes" app end-to-end.

**Hands-on artifact**
- `uv run wkx-scaffold notes` → new `wkx-notes` repo on GitHub + PR opened against `wkx-platform`.
- After merging both, `https://notes.wkx.dev` is live within 10 minutes of starting.

---

## M9 · On-prem mirror — Size: M

**Deliverables**
- Idempotent `host/bootstrap.sh` for the home Ubuntu server:
  - Installs Docker + Compose plugin
  - Creates `/srv/data/home/`
  - Creates `platform` user, pulls platform repo
  - Starts platform Compose stack with `--env home`
- Platform Compose has a `home` profile / env-file:
  - Caddy listens on the LAN IP, not 0.0.0.0
  - No Cloudflare DNS-01; Caddy serves over HTTP only (or self-signed for HTTPS, LAN trust)
  - No CloudWatch agent (system journal only)
- Optional: mDNS responder so `<service>.local` resolves on the LAN.

**Hands-on artifact**
- Run `bootstrap.sh` on the home server.
- Deploy a private project, accessing it from a laptop on home wifi.

---

## M10 · Hardening + backups — Size: M

**Deliverables**
- IAM least-privilege audit: every policy reviewed and tightened.
- Backups:
  - EBS snapshots daily, 7-day retention, via Data Lifecycle Manager.
  - Restic on the box: daily backup of `/srv/data` to S3, encrypted with a passphrase stored in SSM.
- Restore drill: nuke a service's `/srv/data/<service>/<env>/` directory and restore from restic. Verify the service comes back healthy.
- Runbooks (`docs/runbooks/`):
  - Recover from full instance loss
  - Resize the box
  - Add a TLD (first-class app onboarding)
  - Rotate Cloudflare API token
- **Buy 1-yr Compute Savings Plan** sized at ~USD $17/mo (covers t4g.medium 24/7).

**Hands-on artifact**
- Restore a project's data from backup; service comes back healthy.
- Savings Plan visible on the next AWS bill.

---

## M11 · *(Deferred)* Per-branch preview environments — Size: M

The foundation (env-aware namespacing, `mem_limit`/`cpus`, ECR lifecycle, deploy `--env` flag) lands in earlier milestones. M11 wires up the actual feature.

**Deliverables**
- GHA workflow on PR open: deploys with `--env=pr-<N>`; comments PR with the URL.
- GHA workflow on PR close: tears down the env (Caddy snippet removed, Compose project down, data dir removed, ECR tag deleted).
- Cron sweeper Lambda or systemd timer: weekly check for orphaned `pr-*` envs whose PRs are closed; tear down.
- Capacity guardrail: refuse to deploy a new preview if more than N (configurable) are already running.

**Hands-on artifact**
- Open a PR → comment with `https://<service>-pr-42.wkx.dev` appears within minutes.
- Close the PR → next visit returns 404; resources cleaned up.
