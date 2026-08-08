# WKX Platform Roadmap

Build order, deliverables, and hands-on artefact at every milestone.

For the full design rationale, see [docs/superpowers/specs/2026-05-01-wkx-platform-design.md](docs/superpowers/specs/2026-05-01-wkx-platform-design.md).

M0 to M5 are complete. Carry-forward notes live under the most recently completed milestone.

## Contents

| Milestone | Size | Status |
|-----------|------|--------|
| [M0: Prerequisites](#m0-prerequisites) | S | ✅ Complete |
| [M1: Networking + DNS skeleton](#m1-networking--dns-skeleton) | M | ✅ Complete |
| [M2: Graviton host](#m2-graviton-host) | M | ✅ Complete |
| [M3: Caddy + TLS](#m3-caddy--tls) | L | ✅ Complete |
| [M4: Observability](#m4-observability) | M | ✅ Complete |
| [M5: Secrets + config](#m5-secrets--config) | M | ✅ Complete |
| [M6: CI/CD](#m6-cicd) | L | ⬜ Next |
| [M6.1: Platform CI/CD](#m61-platform-cicd) | M | ⬜ Not started |
| [M7: Auto-upgrades](#m7-auto-upgrades) | M | ⬜ Not started |
| [M8: "Add a project" workflow](#m8-add-a-project-workflow) | L | ⬜ Not started |
| [M9: On-prem mirror](#m9-on-prem-mirror) | M | ⬜ Not started |
| [M10: Hardening + backups](#m10-hardening--backups) | M | ⬜ Not started |
| [M11: Per-branch preview environments](#m11-per-branch-preview-environments) | M | ⬜ Deferred |

**Sizes:** S = ≤ a session. M = a focused weekend or 2 evenings. L = several sessions, expect debugging.

**Critical path:** M0 → M1 → M2 → M3 is sequential. M4/M5 can run in parallel after M3. M6.1 follows M6 (it reuses M6's scan gate and deploy machinery for the platform repo itself). M7–M10 are independently orderable. M11 is opt-in.

---

## M0: Prerequisites

**Deliverables**
- [x] Fresh AWS management account (new email alias, e.g. `you+aws-mgmt@example.com`).
- [x] AWS Organisations enabled on the management account.
- [x] Platform member account created (email alias `you+aws-platform@example.com`).
- [x] IAM Identity Center on the mgmt account; SSO permission set granting access to the platform account.
- [x] Cloudflare account exists. (Zone-scoped API token is created in M1 after the zone exists; M0 just needs login access.)
- [x] Local tools installed: Terraform, Docker Desktop, mise/uv, GitHub CLI.

**Hands-on artefact**
- [x] Log in to the platform account via IAM Identity Center SSO.
- [x] `terraform version`, `docker version`, `aws sts get-caller-identity` all return successfully.

**Notes**
- `<APP_DOMAIN>` (Mode-1 per-app domains) remains a placeholder through M10. `wingkongexchange.dev` is registered in M1.

---

## M1: Networking + DNS skeleton

**Deliverables**
- [x] Terraform state backend in the platform account: S3 bucket (versioned, encrypted) with S3-native state locking (`use_lockfile`). No DynamoDB lock table (see the M1 plan for rationale).
- [x] VPC with one public subnet, IGW, default route, IPv6 enabled.
- [x] Security groups:
  - `web`: allows 443 only from Cloudflare IPv4 + IPv6 ranges (via Terraform data source pulling Cloudflare's published list). No port 80: Cloudflare reaches the origin over HTTPS (Full-strict), certs are DNS-01.
  - `host-egress`: allows all outbound.
  - **No port 22 open.**
- [x] Cloudflare zone for `wingkongexchange.dev`.
- [x] All per-project Terraform modules **require** an `env` input with no default. Account-level/host-level resources don't use the env dimension.
- [x] **AWS resource tagging strategy.** Standardised tags applied to every Terraform-managed AWS resource via the AWS provider's `default_tags` block. Required tag keys:
  - `Project` = `wkx` (always)
  - `ManagedBy` = `terraform` (always)
  - `Env` = `<env>` (where the resource has an env dimension; omitted for host/account-level)
  - `Service` = `<service>` (where the resource is per-service; omitted for shared/platform)
  - `Repo` = `wkx-platform` or `wkx-<project>` (the GitHub repo that owns this resource's code)
  Activate cost allocation tags in the Billing console for `Project`, `Env`, `Service` so per-env / per-service spend is queryable.

**Hands-on artifact**
- [x] `dig wingkongexchange.dev NS` returns Cloudflare nameservers.
- [x] `terraform plan` runs clean from a fresh checkout.

---

## M2: Graviton host

**Deliverables**
- [x] EC2 t4g.medium in the public subnet, ARM64 Ubuntu 26.04 AMI resolved via Canonical's SSM public parameter (never a hardcoded AMI ID).
- [x] Elastic IP attached.
- [x] IAM instance profile granting:
  - SSM Session Manager + RunCommand
  - ECR pull
  - CloudWatch Logs/Metrics write
  - SSM Parameter Store read by `/wkx/*` path (broad scope; service-first paths make per-service IAM the natural granularity, deferred to the M2 plan)
  - S3 write to the backups bucket (grant deferred to M10 alongside the bucket itself; see the M2 design spec)
- [x] cloud-init user-data (`host/cloud-init.yaml`) installs:
  - Docker + Compose plugin
  - SSM agent (usually preinstalled), CloudWatch agent
  - Mounts EBS gp3 to `/srv/data` (per-service subdirs created at deploy time)
  - Creates `platform` user

**Hands-on artifact**
- [x] `aws ssm start-session --target <instance-id>` connects without SSH.
- [x] On the box: `docker run hello-world` works; `df -h /srv/data` shows the mounted volume.

---

## M3: Caddy + TLS

**Deliverables**
- [x] `platform/compose.yml` deployed to the box. Caddy image is custom-built via `xcaddy` with the `caddy-dns/cloudflare` plugin (small Dockerfile in `platform/caddy/`, image pushed to ECR).
- [x] Caddy obtains wildcard cert for `*.wingkongexchange.dev` via DNS-01 using the Cloudflare API token (stored in SSM at M3 by Terraform; M5 generalises the render tooling).
- [x] Caddy config: top-level `Caddyfile` does `import /etc/caddy/Caddyfile.d/*.caddy` (snippets are flat `<service>-<env>.caddy` files; Caddy import globs allow one wildcard).
- [x] "hello" smoke-test app deployed as a Compose service (initially in the platform repo; extracted to its own repo at M6).
- [x] Cloudflare DNS A + AAAA records for `hello.wingkongexchange.dev` pointing at the EIP, proxy mode ON (AAAA targets the pinned static IPv6; the EIP is IPv4-only).
- [x] Origin SG hardened to Cloudflare IP ranges only (delivered in M1; verified live in M3).
- [x] cloud-init gains git + aws-cli (deploy-model prerequisites); applying replaced the Host (ADR 0017).

**Hands-on artifact**
- [x] `https://hello.wingkongexchange.dev` returns 200 with valid TLS in a browser.
- [x] `curl -sI` against the EIP directly is blocked (proves SG works).

---

## M4: Observability

**Deliverables**
- [x] CloudWatch agent config ships (the agent is Layer 2 host tooling, ADR 0021):
  - syslog → `/wkx/platform/<env>` (platform occupies the service slot for host-level emissions; decided at M4)
  - host metrics: CPU, memory, disk, network
- [x] Docker container logs → `/wkx/<service>/<env>` via the `awslogs` log driver in cloud-only `compose.cloud.yml` overlays (ADR 0020; agent-tailed JSON files cannot be routed per service).
- [x] One log group per service, created by Terraform.
- [x] CloudWatch dashboard: CPU, memory, disk, network, request rate (from Caddy access logs).
- [x] Host alarms: disk ×2, memory, CPU usage, CPU credit balance.
  - No CloudWatch billing alarm (decided at the M4 grill, 2026-07-06): the wallet guard is the `wkx-org-monthly` budget in `infra/mgmt/` (80% actual / 100% forecasted of USD $45), which avoids the irreversible payer-account billing-alerts preference and cross-region SNS plumbing that a member-account alarm would need.
- [x] Verify the CloudWatch agent deb against its published GPG signature before install (M2 installs it unverified over HTTPS).

**Hands-on artifact**
- [x] Tail Caddy and hello logs in the CloudWatch console.
- [x] Force a host alarm in test mode → email arrives at the configured address.

---

## M5: Secrets + config

**Deliverables**
- [x] SSM Parameter Store namespace `/wkx/<service>/<env>/<KEY>` (live since M3; the Caddy token was its first tenant).
- [x] `tools/secrets/render-env.sh` plus `render-env.py` (bash + aws-cli + stdlib python3, ADR 0022): reads a Parameter namespace by path and renders the Env-file at deploy time. Fail closed, atomic, 0600, values never logged. The uv-packaged Python helper originally planned here was dropped; Python lands under `tools/` when a tool outgrows bash (ADR 0022).
- [x] Compose env-file path standardised at `/srv/secrets/<service>/<env>.env` (created by cloud-init on the root volume, regenerated on deploy, never on the Data volume; applying replaced the Host, ADR 0017). Compose consumes it with `env_file` long syntax (`format: raw`, `required: true`).
- [x] Instance role read-by-path (in place since M3); deploy script (M6) re-renders before `compose up`.
- [x] IMDS hop limit dropped to 1 (ADR 0023): containers cannot reach the instance role's credentials.

**Hands-on artifact**
- [x] Set `/wkx/hello/prod/MESSAGE = "hello world"`.
- [x] Run deploy → page shows the message.
- [x] Update parameter, redeploy → page shows new message.

### Carry-forward

- **M6**: the deploy script calls `tools/secrets/render-env.sh` verbatim and must treat any non-zero render exit as a deploy failure. A missing flag VALUE exits 1, not the documented 2, so do not branch on exit codes.
- **M6**: after any Host replacement the Caddy snippet must be re-rendered (`hello/caddy.snippet` → `/etc/caddy/Caddyfile.d/hello-prod.caddy`, with the platform-owned `Caddyfile.d` dir recreated first). Done by hand in M5 and recorded in `m5-infra-state.local.md`; the deploy script should absorb it.
- **M8**: the `template/` compose file should copy hello's `env_file` block, comment and all, so the render-before-up contract survives the copy.
- **Operations**: after any Host replacement, `wkx-host-cpu-credits` sits in genuine ALARM for roughly 5 to 6 hours while the credit bank refills (standard mode). Expected, and it self-resolves.
- **Security**: a red team security review ran on 2026-07-10 against the repo and the public edge. The report stays out of the repo (`.scratch/`, gitignored). Its actionable findings are woven into M6 to M10 below, tagged F-001 to F-010; findings assessed as not actionable on this single-host architecture become the M10 risk-acceptance ADRs.

---

## M6: CI/CD

**Deliverables**
- [ ] Terraform module `ecr-repo` creates an ECR repo + the IAM role/trust for OIDC GHA push, scoped per project. Includes lifecycle policy: expire all images over 30 days. The finer per-env split (a shorter `pr-*` preview-tag rule) is deferred to M11 with the preview-env feature that produces those tags. Older rollbacks rebuild from git. The `ecr-repo` module takes no `env` input: an ECR repository is per-service, not per-env (one repo per service holds every env's images, the `<sha>` tag decides which env deploys).
- [ ] GitHub OIDC provider configured in the platform account.
- [ ] GHA workflow template:
  - Build multi-stage container (`Dockerfile` targets `linux/arm64` by default).
  - Scan the built image with Trivy (`--ignore-unfixed`); fail the job on high or critical findings that have a fix (the deploy gate, ADR 0025).
  - Push to ECR with tag `<sha>`.
  - Build the deploy bundle (compose file, `compose.cloud.yml` overlay, Caddy snippet, deploy script, render script) and upload it to the deploy bucket under the project's own sha-addressed prefix (ADR 0024).
  - Trigger deploy via `aws ssm send-command`, passing only the bundle key. The on-box deploy script:
    - Pulls and unpacks the bundle.
    - Renders the Env-file from SSM (using the M5 render script), then runs `docker compose -p <service>-<env> up -d` (render before up: Compose consumes the Env-file with `required: true`, so it must exist first).
    - Drops the project's Caddy snippet at `/etc/caddy/Caddyfile.d/<service>-<env>.caddy` and reloads Caddy. The deploy script owns both the snippet drop and the reload; Caddy does not pick the snippet up on its own.
- [ ] Extract "hello" to its own **public** repo `wkx-hello` (it carries no secrets and doubles as the worked example of the platform contract) and wire it through the new pipeline.
- [ ] Deploy script (`tools/deploy/`) **requires** `--env` with no default. Forgetting it errors out with valid env patterns. CI workflows hardcode their target env (PR-open: `pr-<N>`; main-merge: `prod`).
- [ ] Parameterise the `awslogs-group` env in the `compose.cloud.yml` overlays (hardcoded `prod` since M4, fine for its prod-only scope) so PR-env container logs land in `/wkx/<service>/<env>` rather than the prod group.
- [ ] Deploy workflow gates on an in-pipeline Trivy scan (`--ignore-unfixed`) of the built image: the job fails on high or critical findings that have a fix. ECR scan-on-push stays enabled but informational, never gating. No image pushed before M6 had actually been scanned by ECR: buildx wraps each image in an OCI index carrying a provenance attestation, and ECR silently refuses to scan an OCI index, so the old scan-on-push gate would have gated on nothing (F-006, ADR 0025).
- [ ] Guard-rail, verified in the role policy: the GHA OIDC deploy role gets ECR push, `ssm send-command`, and `PutObject` on its own deploy-bucket prefix, never any state-bucket access. State carries the DNS-01 token, so a state-reading CI role would turn an Actions compromise into DNS control of the zone; the deploy-bucket prefix is scoped per project so one project's CI cannot write another's bundle (F-001, ADR 0024).
- [ ] hello implements `do_HEAD` (same headers as `do_GET`, no body), landed during the extraction to `wkx-hello`. `BaseHTTPRequestHandler` otherwise answers HEAD with 501, which breaks clean uptime checks and follows the app into every project copied from it (F-010).
- [ ] Healthcheck contract: every Service's `compose.yml` defines a `healthcheck`, and the deploy script waits for the new container to report healthy before it drops the Caddy snippet and reloads. A container that never becomes healthy fails the deploy and never receives traffic. The reference project carries the block so the contract copies into every project.
- [ ] Rollback has no escape hatch: `git revert` on the app repo followed by a rebuild and redeploy is the only rollback path. There is no "redeploy an older image" button and no image kept past the lifecycle window as a rollback store; a rollback is a normal forward deploy of the reverted commit. This keeps one code path for every deploy and keeps git the single source of what is live.

**Hands-on artifact**
- [ ] Push to `wkx-hello` main → deployed in under 2 minutes.
- [ ] Roll back via `git revert` → previous version live.

---

## M6.1: Platform CI/CD

M6 puts every `wkx-*` app repo on the pipeline. The platform repo builds and ships two things of its own, the Caddy image and the platform stack, and until now both moved by hand. M6.1 puts the platform repo on the same rails.

**Deliverables**
- [ ] CI for the platform repo: on every PR, lint and test the code that already has tooling. `terraform fmt -check`, `terraform validate`, and `terraform test` across the roots (`bootstrap/`, `aws/`, `cloudflare/`, `mgmt/`); shellcheck the bash under `host/` and `tools/`; and the `docs/standards/python.md` toolchain (ruff, ty, pytest) for anything under `tools/` once Python lands there.
- [ ] Caddy image pipeline: build `platform/caddy/` through the same steps as an app image, the Trivy scan gate included (ADR 0025), and push to the `wkx/caddy` ECR repo, replacing the manual M3 build.
- [ ] Platform-stack deploys via SSM RunCommand: a `main`-merge deploys the platform stack (`platform/compose.yml` plus its `compose.cloud.yml` overlay and Caddyfile) to the Host with the same bundle-and-send-command mechanism the apps use (ADR 0024), rather than a hand-run `docker compose` over an SSM session.
- [ ] The platform stack carries the `prod` env like any other deploy (`platform-prod` on the cloud Host), so its deploy names `--env prod` explicitly, never defaulted.

**Hands-on artifact**
- [ ] Push a Caddyfile change to `wkx-platform` main → the platform stack redeploys and serves the change within minutes, no SSM session.
- [ ] Open a PR with a `terraform fmt` violation → CI fails before merge.

---

## M7: Auto-upgrades

**Deliverables**
- [ ] Renovate enabled (GitHub-hosted free tier). Configurations cover:
  - App deps (uv lock files)
  - Dockerfile base images
  - Compose images
  - Terraform providers
  - GitHub Actions versions
- [ ] `renovate.json` policy:
  - Auto-merge minor + patch when CI is green.
  - Major versions stay manual.
- [ ] Base images pinned by digest, with Renovate refreshing the digests. The mutable `python:3.13-slim` and `caddy:2` tags mean rebuilding an old commit can pull different base image content (F-006).
- [ ] Ubuntu unattended-upgrades enabled on the box for security patches. Cheap to pull forward: it is a small cloud-init addition that can ride the next Host replacement rather than wait for this milestone (F-007).

**Hands-on artifact**
- [ ] First Renovate auto-PR appears in some repo, CI passes, it auto-merges.
- [ ] `unattended-upgrade --dry-run` on the box shows expected behavior.

---

## M8: "Add a project" workflow

**Deliverables**
- [ ] Platform contract hardening, landed before the template freezes the contract into every future repo (F-003, F-004, F-005):
  - Named Caddy `(security_headers)` snippet imported by every app snippet, covering `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, and a frame-ancestors CSP. The baseline must be a snippet each host block imports. Headers set in the wildcard block never reach the more-specific app host blocks, because Caddy routes each request to its most specific site block.
  - HSTS zone-wide via Cloudflare's `security_header` zone setting in Terraform.
  - Free-plan Cloudflare edge baseline in Terraform: Bot Fight Mode, the one free rate-limiting rule, browser integrity check.
  - Hardened Compose defaults in `platform/`, hello, and `template/`: `cap_drop: [ALL]`, `security_opt: [no-new-privileges:true]`, `pids_limit`, plus `read_only` with `tmpfs` where the service allows it. Caddy keeps `NET_BIND_SERVICE` and its writable `/data` and `/config` volumes.
- [ ] Reference project at `wkx-platform/template/`, a real, CI-tested working app (the `hello` smoke-test app from M3 doubles as the canonical reference). Contains:
  - `Dockerfile` (multi-stage, ARM64; flag for amd64 opt-in)
  - `compose.yml` (service + named volume + `mem_limit` + `cpus` + the hardening defaults above)
  - `caddy.snippet` (env-templated host block)
  - `.github/workflows/deploy.yml`
  - `renovate.json`
  - `.devcontainer/`
  - `README.md` with deploy instructions
- [ ] `wkx-scaffold` CLI in `tools/scaffold/` (Python, packaged with uv per `docs/standards/python.md`). Behaviour:
  1. Clone `wkx-platform/template/` into a new working directory `wkx-<name>/`.
  2. Substitute `<name>`, `<port>`, `<hostname>` (and a few other placeholders) across all files via plain string replace.
  3. `git init`, initial commit.
  4. `gh repo create wkx-<name> --private --push`.
  5. Open a PR against `wkx-platform` adding `infra/projects/<name>.tf` (uses the M6 `ecr-repo` module).
- [ ] Platform contract documented in `wkx-platform/CLAUDE.md` so AI agents can extend new projects in a conformant way.
- [ ] Demo: scaffold and deploy a SQLite-backed "notes" app end-to-end. Demo data is disposable by design; apps with data worth keeping wait for the M10 backup and restore controls (F-008).

**Hands-on artifact**
- [ ] `uv run wkx-scaffold notes` → new `wkx-notes` repo on GitHub + PR opened against `wkx-platform`.
- [ ] After merging both, `https://notes.wingkongexchange.dev` is live within 10 minutes of starting.

---

## M9: On-prem mirror

**Deliverables**
- [ ] Idempotent `host/bootstrap.sh` for the home Ubuntu server:
  - Installs Docker + Compose plugin
  - Creates `/srv/data/home/`
  - Creates `platform` user, pulls platform repo
  - Starts platform Compose stack with `--env home`
- [ ] Platform Compose has a `home` profile / env-file:
  - Caddy listens on the LAN IP, not 0.0.0.0
  - No Cloudflare DNS-01; Caddy serves over HTTP only (or self-signed for HTTPS, LAN trust)
  - No CloudWatch agent (system journal only)
- [ ] Optional: mDNS responder so `<service>.local` resolves on the LAN.

**Hands-on artifact**
- [ ] Run `bootstrap.sh` on the home server.
- [ ] Deploy a private project, accessing it from a laptop on home wifi.

---

## M10: Hardening + backups

**Deliverables**
- [ ] IAM least-privilege audit: every policy reviewed and tightened.
- [ ] Terraform state treated as secret-bearing: the DNS-01 token lives in state by design, so audit the state bucket for operator-only access and confirm encryption and versioning still hold (F-001).
- [ ] ADRs recording the risks the security review surfaced and this architecture accepts (F-002, F-009): single-host blast radius (the host role reads all of `/wkx/*`, and docker group membership is root-equivalent, so host compromise crosses every service boundary regardless of IAM scoping) and open host egress (no NAT or egress proxy per the cost constraints). Weigh VPC flow logs as compensating detection for the egress acceptance.
- [ ] Backups (F-008):
  - EBS snapshots daily, 7-day retention, via Data Lifecycle Manager.
  - Restic on the box: daily backup of `/srv/data` to S3, encrypted with a passphrase stored in SSM.
- [ ] Restore drill: nuke a service's `/srv/data/<service>/<env>/` directory and restore from restic. Verify the service comes back healthy.
- [ ] Runbooks (`docs/runbooks/`):
  - Recover from full instance loss
  - Resize the box
  - Add a TLD (first-class app onboarding)
  - Rotate Cloudflare API token (`terraform apply -replace` on the token resource, then re-render and redeploy Caddy; also the response if Terraform state exposure is ever suspected, F-001)
- [ ] **Buy 1-yr Compute Savings Plan** sized at ~USD $17/mo (covers t4g.medium 24/7).

**Hands-on artifact**
- [ ] Restore a project's data from backup; service comes back healthy.
- [ ] Savings Plan visible on the next AWS bill.

---

## M11: Per-branch preview environments

The foundation (env-aware namespacing, `mem_limit`/`cpus`, ECR lifecycle, deploy `--env` flag) lands in earlier milestones. M11 wires up the actual feature.

**Deliverables**
- [ ] GHA workflow on PR open: deploys with `--env=pr-<N>`; comments PR with the URL.
- [ ] GHA workflow on PR close: tears down the env (Caddy snippet removed, Compose project down, data dir removed, ECR tag deleted).
- [ ] Cron sweeper Lambda or systemd timer: weekly check for orphaned `pr-*` envs whose PRs are closed; tear down.
- [ ] Capacity guardrail: refuse to deploy a new preview if more than N (configurable) are already running.

**Hands-on artifact**
- [ ] Open a PR → comment with `https://<service>-pr-42.wingkongexchange.dev` appears within minutes.
- [ ] Close the PR → next visit returns 404; resources cleaned up.
