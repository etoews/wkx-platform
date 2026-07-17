# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

This repo has left the pure design phase. Live today: `infra/` (four Terraform roots: `bootstrap/`, `aws/`, `cloudflare/`, `mgmt/`, all applied; M1 network, M2 Graviton host, and the management-account budgets), `host/cloud-init.yaml` (the cloud Host bootstrap; installs git + aws-cli as of M3, and the GPG-verified CloudWatch agent, configured from SSM, as of M4), and `platform/` plus `hello/` (the Platform stack: Caddy behind Cloudflare with one wildcard cert, flat snippet dir; and the `hello` smoke-test app; M3 complete). M4 observability is live (log groups, alarms, and dashboard in `infra/aws/`; agent config in `host/cloudwatch-agent.json`; `compose.cloud.yml` overlays beside each compose file). M5 secrets + config is live (`tools/secrets/` render script per ADR 0022, `/srv/secrets` via cloud-init, IMDS hop limit 1 per ADR 0023, Host replaced). Still to come milestone by milestone per `ROADMAP.md`: Python tooling under `tools/` when a tool outgrows bash (ADR 0022) and the reference project under `template/` (M8). The design spec, milestone plans, ADRs under `docs/adr/`, and the `CONTEXT.md` glossary remain the sources of truth.

Build, lint, and test tooling exists for the infrastructure code: `terraform test` runs invariant tests in `infra/aws/` and `infra/mgmt/`, and `terraform fmt` and `terraform validate` apply to all roots (`bootstrap/`, `aws/`, `cloudflare/`, `mgmt/`). Beyond Terraform, relevant operations include:

- Reading the design spec to answer "why" questions about decisions.
- Reading or extending milestone plans (`docs/superpowers/plans/<date>-<m#>-<name>.md`) which use `- [ ]` checkbox syntax so an agent can execute them task by task.
- Editing the `docs/setup/` state docs (`m0-account-state.md` plus the per-milestone `m<N>-infra-state.md` files; all public-safe templates whose gitignored `*.local.md` siblings hold real account IDs and must never be committed).

Layout for the reference project still to land (`template/`) is described in §5 of the design spec.

## Architecture in one paragraph

A single ARM Graviton EC2 instance in `ap-southeast-2` runs everything via Docker Compose, fronted by Caddy (TLS + routing) with Cloudflare in front for DNS/WAF/DDoS. Deploys flow `git push` → GitHub Actions (OIDC) → ECR + `aws ssm send-command` → on-box pull and `docker compose up -d`. The same Compose stack runs on a home Ubuntu server (LAN-only), with profile flags toggling the Cloudflare/CloudWatch differences. Four layers stack cleanly: **infra (Terraform)** → **host bootstrap (cloud-init / bash)** → **platform services (Caddy, agents)** → **apps (per-project repos)**. See §3, §4, §5 of `docs/superpowers/specs/2026-05-01-wkx-platform-design.md` for the full picture.

## Multi-repo model

This is the **platform repo** (`wkx-platform`). Each application lives in its own `wkx-<name>` repo, scaffolded by copying `template/` and substituting name/port/hostname (no cookiecutter/copier; the platform contract documented here is the spec). Cross-cutting changes ("add HEALTHCHECK to every Dockerfile") are handled by AI fanning out PRs to the `wkx-*` repos rather than templating tools.

## Invariants every change must respect

These are non-negotiable design rules baked into the spec. They are not enforced by tooling yet, so a reviewer (human or AI) must hold the line.

1. **`env` is always explicit, never defaulted.** Per-project Terraform modules require an `env` input with no default. The deploy script requires `--env` with no default. CI workflows hardcode their target env (`pr-${{ github.event.number }}` for PR-open, `prod` for main-merge). Account-level / host-level resources have no env dimension and must not gain one.
2. **No SSH on the box.** Port 22 stays closed. All access is via SSM Session Manager. Do not add a key pair, security group rule, or bastion.
3. **Origin SG accepts 443 only from Cloudflare IPv4 + IPv6 ranges.** No port 80: Cloudflare reaches the origin over HTTPS in Full (strict) SSL mode, Caddy issues certs via DNS-01, and the HTTP to HTTPS redirect happens at Cloudflare's edge. The ranges are pulled via a Terraform data source against Cloudflare's published list so it stays current.
4. **ARM64 is the default container target.** `amd64` is opt-in per project (for things destined for the x86 home server) via multi-arch build.
5. **AWS resources carry the standard tag set** via the provider's `default_tags` block: `Project=wkx`, `ManagedBy=terraform`, plus `Env`, `Service`, `Repo` where applicable. `Project`, `Env`, `Service` are activated cost-allocation tags, so per-env / per-service spend stays queryable.
6. **No ALB, no NAT Gateway, no RDS, no second region, no separate staging account.** Each was considered and rejected on cost/scope grounds (see §8.3 of the spec). Adding any of them is a design change, not an implementation detail.
7. **Public files never carry real account state.** Real AWS account IDs, IdC ARNs, Cloudflare account/zone IDs live in `docs/setup/*.local.md` (gitignored). The committed `.md` siblings are public-safe templates with placeholder values. This covers **every** committed file, not just setup templates: plan and spec docs under `docs/superpowers/` must use placeholders (`<PLATFORM_ACCOUNT_ID>`, `<CLOUDFLARE_ACCOUNT_ID>`, etc.) too, never the real identifiers.

## Naming patterns (from the env model)

When generating resources, follow §6 of the design spec exactly:

| Resource              | Pattern                                          |
|-----------------------|--------------------------------------------------|
| Hostname (Mode 3)     | prod: `<service>.wingkongexchange.dev` · else: `<service>-<env>.wingkongexchange.dev` |
| Compose project       | `<service>-<env>` (via `docker compose -p`)      |
| Caddy snippet         | `/etc/caddy/Caddyfile.d/<service>-<env>.caddy`   |
| SSM Parameter         | `/wkx/<service>/<env>/<KEY>`                     |
| CloudWatch log group  | `/wkx/<service>/<env>`                           |
| Data dir              | `/srv/data/<service>/<env>`                      |
| ECR tag               | `<sha>` or `<branch>-<sha>`                      |

`<APP_DOMAIN>` is an intentional placeholder through M10. `<APPS_APEX>` is now `wingkongexchange.dev` (registered in M1).

## Working on a milestone

The repo's unit of implementation is the **milestone**, not the PR. Recommended flow:

1. Open `ROADMAP.md` and the relevant section of the design spec for the next milestone.
2. Use `/brainstorm-with-docs`
3. Write or update an implementation plan under `docs/superpowers/plans/<date>-m<N>-<slug>.md` using checkbox syntax so an agent can execute it task by task.
4. Use `/handoff create a handoff doc similar to the ones in @.superpowers/handoff/ for building this milestone`
5. Use `/clear`
6. Use `/superpowers:subagent-driven-development the latest handoff doc in @.superpowers/handoff/`
7. Execute the plan one task at a time. When the milestone produces verification commands ("hands-on artifacts" in the roadmap), run them and capture results.
8. Use `/security-review`
9. Pause and I'll decide when to ff merge and push.
10. Update the ROADMAP.md and tick off everything that was completed. Make any carry-forward notes a subsection of the most recently completed milestone.

Do not jump milestones. The critical path `M0 → M1 → M2 → M3` is sequential; later milestones assume earlier deliverables exist.

## Python

Anything Python, in this repo or in a `wkx-*` app repo, follows [`docs/adr/0000-python-standards.md`](docs/adr/0000-python-standards.md). Read it before writing, reviewing, or scaffolding Python. It is the distillation of the machine-wide standards in `~/dev/etoews/python/PROJECT.md` and fixes the toolchain (uv, ruff, pytest, ty), the two shapes Python takes here (stdlib-only scripts on the Host, uv-packaged tools under `tools/`), and the bar for typing, docstrings, logging, secrets, and CI. Bash comes first: Python only arrives when a tool outgrows bash (ADR 0022).

## Writing conventions in this repo

- New Zealand English in prose.
- No em dashes; use commas, parentheses, or a sentence break instead.
- Architecture and flow diagrams in markdown use mermaid code blocks, not ASCII art.
