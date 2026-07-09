# M5: Secrets + Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSM Parameter Store is the single source of secrets and config for every Service; a committed bash script renders `/wkx/<service>/<env>/*` into the Env-file at `/srv/secrets/<service>/<env>.env`, hello proves it end to end via `MESSAGE`, and containers can no longer reach the instance role's credentials (IMDS hop limit 1).

**Architecture:** A ~30-line bash wrapper (`tools/secrets/render-env.sh`) calls `aws ssm get-parameters-by-path` and pipes the JSON through a stdlib-only python3 transform (`render-env.py`) that fails closed on anything the env-file format cannot represent, then writes atomically (0600). Compose files consume the Env-file with `env_file` long syntax (`format: raw`, `required: true`). cloud-init creates `/srv/secrets`, which replaces the Host (ADR 0017, accepted); the IMDS drop rides the same apply. Spec: `docs/superpowers/specs/2026-07-10-m5-secrets-config-design.md` (post-grill, commit d92ff98). Decisions: ADR 0022 (bash render), ADR 0023 (IMDS hop limit 1).

**Tech Stack:** bash + aws-cli v2 + python3 stdlib (no packages), Docker Compose `env_file` long syntax, Terraform (aws root), cloud-init, SSM Parameter Store + Session Manager, shellcheck.

## Global Constraints

- `env` is always explicit, never defaulted (ADR 0006). The render script requires `--service` and `--env`; both are shape-validated against `^[a-z][a-z0-9-]*$`.
- No SSH; all box access via `aws ssm start-session` (ADR 0003).
- Committed files never carry real account state (invariant 7): use `<PLATFORM_ACCOUNT_ID>`, `<NEW_INSTANCE_ID>` placeholders; real values go in `docs/setup/*.local.md` (gitignored) only.
- Fail closed everywhere: any key or value the env-file format cannot represent aborts the render; nothing is silently mangled. Values are written raw; the consuming compose files declare `format: raw`.
- Env-files live on the root volume, never the Data volume (M10 snapshots must not capture secrets). Never log parameter values; log counts and key names only.
- Parameter conventions: `<KEY>` is UPPER_SNAKE_CASE; secrets are `SecureString`, non-secret config is `String`; CLI-set Parameters are tagged `Project=wkx`, `Service=<service>`, `Env=<env>`.
- Terraform: `terraform fmt -check`, `terraform validate`, and `terraform test` must pass before the apply. All aws-root commands need `-var-file=terraform.local.tfvars` (tests use their `variables` blocks).
- ADR 0017: the `host/cloud-init.yaml` change replaces the Host. Task 6 does this deliberately, once. Expect `wkx-host-cpu-credits` in ALARM roughly 5 to 6 hours afterwards (known from M4; self-resolves).
- Both bash scripts must be shellcheck-clean (`shellcheck tools/secrets/render-env.sh tools/secrets/test.sh`).
- Prose in NZ English, no em dashes. Diagrams in mermaid.
- Commit style: `feat(m5):`, `infra(m5):`, `docs(m5):`. Work on the existing `feat/m5-secrets-config` branch.
- The hands-on artefacts that define done: set `/wkx/hello/prod/MESSAGE`, render, deploy, page shows it; update the Parameter, re-render, redeploy, page shows the new value.

---

### Task 1: Pre-flight gates (read-only)

**Files:**
- None changed (verification task)

**Interfaces:**
- Produces: confirmation that the box and laptop Compose versions support `env_file` long syntax with `format: raw` (needs Compose >= 2.30); the current hop limit (expected 2) as the before-state; the box's checkout/bring-up procedure location for Task 6.

- [ ] **Step 1: Check Compose versions on both sides**

On the laptop:

```bash
docker compose version
```

On the box:

```bash
aws ssm start-session --target "$(cd infra/aws && terraform output -raw instance_id)"
# in the session:
docker compose version
```

Expected: both report v2.30 or later (the box installs `docker-compose-plugin` from Docker's apt repo, so it is current). If either is older, stop: `format: raw` in Tasks 4 and 5 needs it; upgrade before continuing.

- [ ] **Step 2: Confirm the before-state**

From the laptop:

```bash
aws ec2 describe-instances --instance-ids "$(cd infra/aws && terraform output -raw instance_id)" \
  --query 'Reservations[0].Instances[0].MetadataOptions.{tokens:HttpTokens,hops:HttpPutResponseHopLimit}'
aws ssm get-parameters-by-path --path /wkx/ --recursive --query 'Parameters[].Name'
```

Expected: `tokens: required`, `hops: 2`; the only Parameters are `/wkx/caddy/prod/CLOUDFLARE_API_TOKEN` and the CloudWatch agent config parameter. Note where the on-box checkout and interpolated env-file procedure is recorded (`docs/setup/m3-infra-state.local.md` and `m4-infra-state.local.md`); Task 6 follows it. No commit for this task.

---

### Task 2: The transform (`render-env.py`)

**Files:**
- Create: `tools/secrets/render-env.py`
- Create: `tools/secrets/test.sh` (transform section; Task 3 appends the wrapper section)

**Interfaces:**
- Consumes: nothing (stdlib-only python3; runs under the system interpreter, no packaging).
- Produces: `render-env.py <prefix>` reads `aws ssm get-parameters-by-path` JSON (`{"Parameters":[{"Name":...,"Value":...,"Type":...}]}`) on stdin and writes sorted `KEY=value` lines to stdout; exit 0 on success (including zero Parameters, with a stderr warning), exit 1 on any validation failure, exit 2 on usage error. stderr reports counts and key names, never values. Task 3's wrapper pipes into exactly this contract.

- [ ] **Step 1: Write the failing transform tests**

`tools/secrets/test.sh`:

```bash
#!/usr/bin/env bash
# Tests for the Env-file render (ADR 0022): transform first, wrapper below.
# Usage: ./test.sh   (no AWS access needed; aws is stubbed)
set -uo pipefail
cd "$(dirname "$0")"

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Portable file-mode helper (macOS and Linux).
perms_of() { stat -f%Lp "$1" 2>/dev/null || stat -c%a "$1"; }

# ---------- transform: render-env.py ----------

json_ok='{"Parameters":[
  {"Name":"/wkx/hello/prod/MESSAGE","Value":"kia ora","Type":"String"},
  {"Name":"/wkx/hello/prod/API_KEY","Value":"s3cr3t$#x=\"q\"","Type":"SecureString"}]}'
out=$(printf '%s' "$json_ok" | python3 render-env.py /wkx/hello/prod/ 2>/dev/null)
expected=$(printf 'API_KEY=s3cr3t$#x="q"\nMESSAGE=kia ora')
[ "$out" = "$expected" ] && ok || bad "happy path: sorted, raw values preserved"

out=$(printf '{"Parameters":[]}' | python3 render-env.py /wkx/hello/prod/ 2>"$tmp/err")
{ [ -z "$out" ] && grep -q 'no Parameters' "$tmp/err"; } && ok || bad "empty namespace: empty output plus warning"

printf 'not json' | python3 render-env.py /wkx/hello/prod/ 2>/dev/null && bad "invalid JSON accepted" || ok

json_nl='{"Parameters":[{"Name":"/wkx/hello/prod/PEM","Value":"a\nb","Type":"SecureString"}]}'
printf '%s' "$json_nl" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "newline value accepted" || ok

json_ws='{"Parameters":[{"Name":"/wkx/hello/prod/PAD","Value":" padded ","Type":"String"}]}'
printf '%s' "$json_ws" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "padded value accepted" || ok

json_low='{"Parameters":[{"Name":"/wkx/hello/prod/message","Value":"x","Type":"String"}]}'
printf '%s' "$json_low" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "lowercase key accepted" || ok

json_nest='{"Parameters":[{"Name":"/wkx/hello/prod/db/PASSWORD","Value":"x","Type":"String"}]}'
printf '%s' "$json_nest" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "nested key accepted" || ok

json_out='{"Parameters":[{"Name":"/wkx/other/prod/KEY","Value":"x","Type":"String"}]}'
printf '%s' "$json_out" | python3 render-env.py /wkx/hello/prod/ >/dev/null 2>&1 && bad "outside-prefix name accepted" || ok

printf '%s' "$json_ok" | python3 render-env.py /wkx/hello/prod/ 2>&1 >/dev/null | grep -q 's3cr3t' \
  && bad "stderr leaked a value" || ok

echo "transform: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
```

Make it executable: `chmod +x tools/secrets/test.sh`

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tools/secrets/test.sh`
Expected: FAIL lines (python3 cannot open `render-env.py`), non-zero exit.

- [ ] **Step 3: Write the transform**

`tools/secrets/render-env.py`:

```python
#!/usr/bin/env python3
"""Transform `aws ssm get-parameters-by-path` JSON into Env-file lines.

Usage: render-env.py <prefix>    (JSON on stdin, env lines on stdout)

Part of the M5 render (ADR 0022). Fails closed: any key or value the
env-file format cannot represent aborts with exit 1. Values pass through
raw; the consuming compose files declare `format: raw`, so no quoting or
interpolation applies. stderr reports counts and key names, never values.
Stdlib only; runs under the Host's system python3.
"""
import json
import re
import sys

KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def fail(message: str) -> int:
    print(f"render-env: {message}", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: render-env.py <prefix>", file=sys.stderr)
        return 2
    prefix = sys.argv[1]
    if not prefix.endswith("/"):
        prefix += "/"

    try:
        doc = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        return fail(f"invalid JSON on stdin: {exc}")

    pairs: dict[str, str] = {}
    for param in doc.get("Parameters", []):
        name = param["Name"]
        value = param["Value"]
        if not name.startswith(prefix):
            return fail(f"{name} is outside {prefix}")
        key = name[len(prefix):]
        if "/" in key:
            return fail(f"{name} nests deeper than {prefix}<KEY>")
        if not KEY_RE.fullmatch(key):
            return fail(f"key {key!r} is not UPPER_SNAKE_CASE")
        if key in pairs:
            return fail(f"duplicate key {key}")
        if "\n" in value or "\r" in value:
            return fail(f"value of {key} contains a line break")
        if value != value.strip():
            return fail(f"value of {key} has leading or trailing whitespace")
        pairs[key] = value

    for key in sorted(pairs):
        sys.stdout.write(f"{key}={pairs[key]}\n")
    if pairs:
        print(f"render-env: {len(pairs)} keys: {' '.join(sorted(pairs))}", file=sys.stderr)
    else:
        print(f"render-env: warning: no Parameters under {prefix}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `tools/secrets/test.sh`
Expected: `transform: 9 passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tools/secrets/render-env.py tools/secrets/test.sh
git commit -m "feat(m5): env-file transform, fail closed, stdlib only"
```

---

### Task 3: The wrapper (`render-env.sh`)

**Files:**
- Create: `tools/secrets/render-env.sh`
- Modify: `tools/secrets/test.sh` (append the wrapper section before the summary lines)

**Interfaces:**
- Consumes: `render-env.py <prefix>` from Task 2 (same directory).
- Produces: `render-env.sh --service <service> --env <env> [--output <path>]`; renders `/srv/secrets/<service>/<env>.env` (0600, atomic, dir 0700) from `/wkx/<service>/<env>/`; exit 0 on success, 1 on render failure, 2 on usage/validation failure. Tasks 6 and 7 call it on the box; M6's deploy script calls it verbatim.

- [ ] **Step 1: Append the failing wrapper tests**

In `tools/secrets/test.sh`, replace the final three lines (`echo "transform: ..."` through `exit 1`) with:

```bash
echo "transform: $pass passed, $fail failed"

# ---------- wrapper: render-env.sh ----------

mkdir -p "$tmp/bin" "$tmp/out"
cat > "$tmp/bin/aws" <<STUB
#!/usr/bin/env bash
echo "\$@" > "$tmp/aws-args"
[ -n "\${STUB_FAIL:-}" ] && exit 1
cat "\$FIXTURE"
STUB
chmod +x "$tmp/bin/aws"

printf '%s' "$json_ok" > "$tmp/fixture-ok.json"

FIXTURE="$tmp/fixture-ok.json" PATH="$tmp/bin:$PATH" \
  ./render-env.sh --service hello --env prod --output "$tmp/out/prod.env" 2>/dev/null
{ [ $? -eq 0 ] && [ "$(cat "$tmp/out/prod.env")" = "$expected" ]; } \
  && ok || bad "wrapper happy path: file content"

[ "$(perms_of "$tmp/out/prod.env")" = "600" ] && ok || bad "wrapper: file mode 600"

grep -q -- 'get-parameters-by-path --path /wkx/hello/prod/ --recursive --with-decryption' "$tmp/aws-args" \
  && ok || bad "wrapper: aws called with path, --recursive, --with-decryption"

FIXTURE="$tmp/fixture-ok.json" PATH="$tmp/bin:$PATH" \
  ./render-env.sh --service '../etc' --env prod --output "$tmp/out/evil.env" 2>/dev/null
{ [ $? -eq 2 ] && [ ! -e "$tmp/out/evil.env" ]; } && ok || bad "wrapper: traversal service rejected"

FIXTURE="$tmp/fixture-ok.json" PATH="$tmp/bin:$PATH" \
  ./render-env.sh --service hello --output "$tmp/out/noenv.env" 2>/dev/null
[ $? -eq 2 ] && ok || bad "wrapper: missing --env rejected"

STUB_FAIL=1 FIXTURE="$tmp/fixture-ok.json" PATH="$tmp/bin:$PATH" \
  ./render-env.sh --service hello --env prod --output "$tmp/out/fail.env" 2>/dev/null
{ [ $? -ne 0 ] && [ ! -e "$tmp/out/fail.env" ] && [ -z "$(find "$tmp/out" -name '.render-env.*')" ]; } \
  && ok || bad "wrapper: aws failure leaves no partial or temp file"

echo "total: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `tools/secrets/test.sh`
Expected: transform tests still pass; wrapper tests FAIL (`./render-env.sh: No such file or directory`), non-zero exit.

- [ ] **Step 3: Write the wrapper**

`tools/secrets/render-env.sh`:

```bash
#!/usr/bin/env bash
# Render a Service's Env-file from its Parameter namespace (ADR 0022).
# Usage: render-env.sh --service <service> --env <env> [--output <path>]
# Reads /wkx/<service>/<env>/ and writes /srv/secrets/<service>/<env>.env
# (0600, atomic; dir 0700). Fail closed; never logs values. --output is
# for tests only. env is always explicit, never defaulted (ADR 0006).
set -euo pipefail

usage() {
  echo "usage: render-env.sh --service <service> --env <env> [--output <path>]" >&2
  exit 2
}

service='' env='' output=''
while [ $# -gt 0 ]; do
  case "$1" in
    --service) service="${2:?}"; shift 2 ;;
    --env)     env="${2:?}"; shift 2 ;;
    --output)  output="${2:?}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$service" ] && [ -n "$env" ] || usage

# Both values build the SSM path and the filesystem path: shape-validate
# to block traversal (grill decision, 2026-07-10).
shape='^[a-z][a-z0-9-]*$'
[[ "$service" =~ $shape ]] || { echo "render-env: invalid --service '$service'" >&2; exit 2; }
[[ "$env" =~ $shape ]] || { echo "render-env: invalid --env '$env'" >&2; exit 2; }

prefix="/wkx/${service}/${env}/"
[ -n "$output" ] || output="/srv/secrets/${service}/${env}.env"
outdir=$(dirname "$output")
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

umask 077
mkdir -p "$outdir"

tmpfile=$(mktemp "$outdir/.render-env.XXXXXX")
trap 'rm -f "$tmpfile"' EXIT

# --recursive so nested Parameters reach the transform and abort loudly
# instead of being silently omitted.
aws ssm get-parameters-by-path \
  --path "$prefix" --recursive --with-decryption --output json \
  | python3 "$here/render-env.py" "$prefix" > "$tmpfile"

mv "$tmpfile" "$output"
trap - EXIT
echo "render-env: wrote $output" >&2
```

Make it executable: `chmod +x tools/secrets/render-env.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `tools/secrets/test.sh`
Expected: `total: 15 passed, 0 failed`, exit 0.

- [ ] **Step 5: shellcheck both scripts**

Run: `shellcheck tools/secrets/render-env.sh tools/secrets/test.sh`
Expected: no output (clean). Install on the laptop with `brew install shellcheck` if missing. Fix any findings rather than suppressing them; if a suppression is genuinely required, use a targeted `# shellcheck disable=SCnnnn` with a one-line reason.

- [ ] **Step 6: Commit**

```bash
git add tools/secrets/render-env.sh tools/secrets/test.sh
git commit -m "feat(m5): render-env.sh wrapper; atomic 0600 env-file render"
```

---

### Task 4: Compose wiring (hello + platform)

**Files:**
- Modify: `hello/compose.yml` (web service)
- Modify: `platform/compose.yml:14-15` (caddy env_file)

**Interfaces:**
- Consumes: the Env-file path convention `/srv/secrets/<service>/<env>.env` (rendered by Task 3's script).
- Produces: both compose files consume Env-files with the long syntax (`format: raw`, `required: true`); Task 6's bring-up depends on render-before-up.

- [ ] **Step 1: Wire hello**

In `hello/compose.yml`, add to the `web` service (after `restart: unless-stopped`):

```yaml
    # Env-file rendered from SSM before every up (ADR 0022). required: true
    # makes render-before-up an ordering contract; format: raw passes
    # values verbatim (no interpolation, no quote processing).
    env_file:
      - path: /srv/secrets/hello/${ENV:?}.env
        required: true
        format: raw
```

- [ ] **Step 2: Wire caddy the same way**

In `platform/compose.yml`, replace:

```yaml
    env_file:
      - /srv/secrets/caddy/prod.env # CLOUDFLARE_API_TOKEN, rendered from SSM
```

with:

```yaml
    # CLOUDFLARE_API_TOKEN, rendered from SSM (ADR 0022): raw values,
    # render-before-up enforced.
    env_file:
      - path: /srv/secrets/caddy/prod.env
        required: true
        format: raw
```

- [ ] **Step 3: Validate both configs resolve**

```bash
mkdir -p /tmp/wkx-envcheck/hello /tmp/wkx-envcheck/caddy
printf 'MESSAGE=check\n' > /tmp/wkx-envcheck/hello/prod.env
printf 'CLOUDFLARE_API_TOKEN=check\n' > /tmp/wkx-envcheck/caddy/prod.env
(cd hello && ENV=prod ECR_REGISTRY=x HELLO_TAG=y \
  docker compose -f compose.yml config >/dev/null) ; echo "hello: $?"
(cd platform && ECR_REGISTRY=x CADDY_TAG=y \
  docker compose -f compose.yml config >/dev/null) ; echo "platform: $?"
```

Expected: both print `0`. Note: `docker compose config` resolves the env_file paths at their absolute locations only when the files exist there; on the laptop `/srv/secrets` does not exist, so `config` may warn or fail on the missing file. If it fails, rerun with the file temporarily created at `/srv/secrets/...` via sudo, or accept a passing `--no-interpolate` structural check; the authoritative validation happens on the box in Task 6. Clean up: `rm -rf /tmp/wkx-envcheck`.

- [ ] **Step 4: Commit**

```bash
git add hello/compose.yml platform/compose.yml
git commit -m "feat(m5): compose env_file long syntax; raw format, required"
```

---

### Task 5: Terraform + cloud-init (code only, no apply)

**Files:**
- Modify: `infra/aws/ec2.tf:48-52` (metadata_options)
- Modify: `infra/aws/tests/host_invariants.tftest.hcl` (hop-limit assertion)
- Modify: `host/cloud-init.yaml` (header comment + runcmd)

**Interfaces:**
- Consumes: existing aws root and cloud-init.
- Produces: the plan Task 6 applies: hop limit 1 (ADR 0023) and `/srv/secrets` creation (0700, `platform`); Task 6's bring-up assumes both.

- [ ] **Step 1: Add the failing invariant assertion**

In `infra/aws/tests/host_invariants.tftest.hcl`, inside `run "host_is_imdsv2_and_cattle"`, after the `http_tokens` assert block, add:

```hcl
  assert {
    condition     = aws_instance.host.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDS hop limit must be 1: containers must not reach instance credentials (ADR 0023)."
  }
```

- [ ] **Step 2: Run the tests to verify the new assertion fails**

Run: `cd infra/aws && terraform test`
Expected: `host_is_imdsv2_and_cattle` FAILS on the new assertion (current hop limit is 2); everything else passes.

- [ ] **Step 3: Drop the hop limit**

In `infra/aws/ec2.tf`, replace the `metadata_options` block with:

```hcl
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # Containers must not reach the instance role's credentials: the role
    # reads every /wkx/* Parameter. Hop limit 1 stops IMDSv2 token
    # responses at the bridge-network boundary (ADR 0023, reverses M2).
    http_put_response_hop_limit = 1
  }
```

- [ ] **Step 4: Create /srv/secrets in cloud-init**

In `host/cloud-init.yaml`:

Header: after the `# M4 added:` line, add:

```yaml
# M5 added: /srv/secrets, the Env-file render target (ADR 0022).
```

In `runcmd`, after the `[snap, install, aws-cli, --classic]` line, add:

```yaml
  # Env-files render into /srv/secrets (ADR 0022): root volume only,
  # platform-owned. Never the Data volume: M10 snapshots must not
  # capture rendered secrets. The platform user cannot create this
  # (root owns /srv), so bootstrap must.
  - [install, -d, -o, platform, -g, platform, -m, '0700', /srv/secrets]
```

- [ ] **Step 5: Verify formatting, validity, and tests**

```bash
cd infra/aws && terraform fmt -check && terraform validate && terraform test
```

Expected: fmt silent, validate `Success!`, all tests pass including the new assertion.

- [ ] **Step 6: Commit**

```bash
git add infra/aws/ec2.tf infra/aws/tests/host_invariants.tftest.hcl host/cloud-init.yaml
git commit -m "infra(m5): IMDS hop limit 1 (ADR 0023); cloud-init creates /srv/secrets"
```

---

### Task 6: Set MESSAGE, apply, replacement bring-up

**Files:**
- None changed (apply + operations task)

**Interfaces:**
- Consumes: everything from Tasks 2 to 5, committed on `feat/m5-secrets-config` (the box checks out this branch).
- Produces: the replaced Host (`<NEW_INSTANCE_ID>`) running with hop limit 1 and `/srv/secrets` from bootstrap; both stacks up; `https://hello.wingkongexchange.dev/` serving the SSM-driven `MESSAGE`. Task 7 updates the Parameter; Task 8 records the state.

- [ ] **Step 1: Create the MESSAGE Parameter**

From the laptop:

```bash
aws ssm put-parameter --name /wkx/hello/prod/MESSAGE --type String --value 'hello world'
aws ssm add-tags-to-resource --resource-type Parameter --resource-id /wkx/hello/prod/MESSAGE \
  --tags Key=Project,Value=wkx Key=Service,Value=hello Key=Env,Value=prod
```

Expected: version 1 created. (`put-parameter` cannot tag and overwrite in one call, hence the second command.)

- [ ] **Step 2: Plan and inspect the replacement**

```bash
cd infra/aws && terraform plan -var-file=terraform.local.tfvars
```

Expected: `aws_instance.host` **must be replaced** (user_data change); `metadata_options` shows hop limit 1 on the new instance; `aws_volume_attachment.data` replaced (stop-before-detach); the EIP association and `aws_ebs_volume.data` are NOT destroyed. If the plan destroys the Data volume or the EIP, stop and investigate before applying.

- [ ] **Step 3: Apply**

```bash
terraform apply -var-file=terraform.local.tfvars
```

Expected: old instance stops (clean unmount), new instance boots, Data volume and EIP reattach. Record the new instance ID as `<NEW_INSTANCE_ID>` for Task 8.

- [ ] **Step 4: Verify the new Host's posture**

```bash
aws ec2 describe-instances --instance-ids "$(terraform output -raw instance_id)" \
  --query 'Reservations[0].Instances[0].MetadataOptions.{tokens:HttpTokens,hops:HttpPutResponseHopLimit}'
```

Expected: `tokens: required`, `hops: 1`.

- [ ] **Step 5: Bring-up on the new box**

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

In the session, as the platform user (`sudo -iu platform`), follow the checkout and interpolated env-file procedure recorded in `docs/setup/m3-infra-state.local.md` / `m4-infra-state.local.md` (clone the repo, `git checkout feat/m5-secrets-config`, recreate `platform/.env` and `hello/.env` with the registry, tags, and `ENV=prod`). Then verify bootstrap created the render target:

```bash
stat -c '%a %U:%G' /srv/secrets
```

Expected: `700 platform:platform`. This line is the cloud-init deliverable proving itself.

- [ ] **Step 6: Render both Env-files with the script**

Still as platform, from the repo checkout:

```bash
tools/secrets/render-env.sh --service caddy --env prod
tools/secrets/render-env.sh --service hello --env prod
stat -c '%a %U:%G' /srv/secrets/caddy/prod.env /srv/secrets/hello/prod.env
```

Expected: stderr reports 1 key (`CLOUDFLARE_API_TOKEN`) and 1 key (`MESSAGE`) respectively, then `wrote ...`; both files `600 platform:platform`. This replaces M3's manual render: same file, now scripted.

- [ ] **Step 7: Start the stacks and verify live**

ECR login, then both stacks (commands per the compose file headers):

```bash
aws ecr get-login-password | docker login --username AWS --password-stdin <PLATFORM_ACCOUNT_ID>.dkr.ecr.ap-southeast-2.amazonaws.com
cd ~/wkx-platform/platform && docker compose -f compose.yml -f compose.cloud.yml -p platform-prod up -d
cd ~/wkx-platform/hello && docker compose -f compose.yml -f compose.cloud.yml -p hello-prod up -d
```

From the laptop:

```bash
curl -s https://hello.wingkongexchange.dev/ | grep 'hello world'
```

Expected: `<h1>hello world</h1>`: the page now serves the SSM Parameter, not the baked-in default. TLS valid (Caddy re-obtained or reloaded the persisted wildcard cert from the Data volume). Expected alarm noise: `wkx-host-cpu-credits` in ALARM 5 to 6 hours (known, self-resolves); all other alarms return to OK. No commit for this task.

---

### Task 7: The update artefact (change MESSAGE live)

**Files:**
- None changed (verification task)

**Interfaces:**
- Consumes: Task 6's running stack and the render script.
- Produces: proof that a Parameter update flows to the page via render + up (the M5 hands-on artefact); the observed recreate behaviour Task 8 documents in the README.

- [ ] **Step 1: Update the Parameter**

From the laptop:

```bash
aws ssm put-parameter --name /wkx/hello/prod/MESSAGE --value 'kia ora, wing kong exchange' --overwrite
```

Expected: version 2.

- [ ] **Step 2: Re-render and redeploy on the box**

In an SSM session, as platform, from the checkout:

```bash
tools/secrets/render-env.sh --service hello --env prod
cd ~/wkx-platform/hello && docker compose -f compose.yml -f compose.cloud.yml -p hello-prod up -d
```

Expected: `up -d` reports the `web` container **Recreated** (changed env-file content changes the service config, which Compose picks up by stopping and recreating; verified against current Compose docs). If it reports `Running` (unchanged) instead, rerun with `up -d --force-recreate` and record that requirement in Task 8's README.

- [ ] **Step 3: Verify the new message**

From the laptop:

```bash
curl -s https://hello.wingkongexchange.dev/ | grep 'kia ora, wing kong exchange'
```

Expected: match. The full M5 hands-on artefact is now demonstrated: set, render, deploy, update, re-render, redeploy. No commit for this task.

---

### Task 8: Docs and amendments

**Files:**
- Create: `tools/secrets/README.md`
- Create: `docs/setup/m5-infra-state.md` (public-safe template; fill the gitignored `.local.md` sibling by hand during this task)
- Modify: `ROADMAP.md` (M5 section; M6 wording check)
- Modify: `CLAUDE.md` (repository state paragraph)

**Interfaces:**
- Consumes: outcomes of Tasks 6 and 7 (`<NEW_INSTANCE_ID>`, observed recreate behaviour).
- Produces: the milestone's documented state; the operator runbook M6's deploy script documentation will link to.

- [ ] **Step 1: Write the operator runbook**

`tools/secrets/README.md`:

````markdown
# tools/secrets

Renders a Service's Env-file from its Parameter namespace (ADR 0022):
`/wkx/<service>/<env>/<KEY>` in SSM Parameter Store becomes
`/srv/secrets/<service>/<env>.env` (0600, atomic, fail closed).

## Render

```bash
tools/secrets/render-env.sh --service hello --env prod
```

Both flags are required; there are no defaults (ADR 0006). Values are
written raw and consumed by Compose with `format: raw`, so no quoting or
interpolation applies. Runs anywhere the aws-cli has credentials: the
Host (instance role), a laptop, or the home server (M9).

## Set a Parameter

Secrets are `SecureString`; non-secret config is `String`. Keys are
UPPER_SNAKE_CASE. Tag every Parameter.

```bash
aws ssm put-parameter --name /wkx/<service>/<env>/<KEY> --type SecureString --value '<value>'
aws ssm add-tags-to-resource --resource-type Parameter --resource-id /wkx/<service>/<env>/<KEY> \
  --tags Key=Project,Value=wkx Key=Service,Value=<service> Key=Env,Value=<env>
```

To update: add `--overwrite` to `put-parameter` (tags persist). Values
must be single-line with no leading or trailing whitespace; the render
aborts otherwise. Then re-render and `docker compose up -d` (Compose
recreates the container when the Env-file content changed).

## Failure modes

The render fails closed and leaves no partial file. Common aborts: a key
that is not UPPER_SNAKE_CASE, a Parameter nested deeper than
`<namespace>/<KEY>`, a multi-line value, aws-cli errors. Zero Parameters
is not an error: an empty Env-file is rendered with a stderr warning.

## Tests

```bash
tools/secrets/test.sh    # stubbed aws; no AWS access needed
shellcheck tools/secrets/render-env.sh tools/secrets/test.sh
```
````

If Task 7 needed `--force-recreate`, replace the recreate sentence in "Set a Parameter" with: "Compose does not pick up the change from the Env-file alone; use `docker compose up -d --force-recreate`."

- [ ] **Step 2: Write the state doc**

`docs/setup/m5-infra-state.md` (public-safe; mirror the structure of `docs/setup/m4-infra-state.md`; real values go only in the gitignored `m5-infra-state.local.md`, which this step also fills in by hand):

```markdown
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
- M5 completed: `<DATE>`
- Hands-on artefacts: page served SSM MESSAGE; Parameter update flowed
  to the page via re-render + up; render posture 600/700 verified.
```

- [ ] **Step 3: Amend ROADMAP.md**

Replace the M5 deliverables list with:

```markdown
**Deliverables**
- SSM Parameter Store namespace `/wkx/<service>/<env>/<KEY>` (live since M3; the Caddy token was its first tenant).
- `tools/secrets/render-env.sh` (bash + aws-cli, ADR 0022): reads a Parameter namespace by path and renders the Env-file at deploy time. Fail closed, atomic, 0600. The uv-packaged Python helper originally planned here was dropped; Python lands under `tools/` when a tool outgrows bash (ADR 0022).
- Compose env-file path standardised at `/srv/secrets/<service>/<env>.env` (created by cloud-init on the root volume, regenerated on deploy, never on the Data volume). Compose consumes it with `env_file` long syntax (`format: raw`, `required: true`).
- Instance role read-by-path (in place since M3); deploy script (M6) re-renders before `compose up`.
- IMDS hop limit dropped to 1 (ADR 0023): containers cannot reach the instance role's credentials.
```

Keep the M5 hands-on artifact block unchanged. In the M6 section, change "Renders env-file from SSM (using the M5 helper)." to "Renders the Env-file from SSM (using the M5 render script)."

- [ ] **Step 4: Refresh the CLAUDE.md repository state paragraph**

In `CLAUDE.md` "Repository state": extend the "Live today" sentence to record M5 (secrets + config: `tools/secrets/` render script per ADR 0022, `/srv/secrets` via cloud-init, IMDS hop limit 1 per ADR 0023, Host replaced) and change "Python tooling under `tools/` (M5 onward)" in the still-to-come sentence to "Python tooling under `tools/` when a tool outgrows bash (ADR 0022)". Note: the working tree already carries an intentional uncommitted user edit to the "Working on a milestone" section; keep it and commit it together with this change.

- [ ] **Step 5: Commit**

```bash
git add tools/secrets/README.md docs/setup/m5-infra-state.md ROADMAP.md CLAUDE.md
git commit -m "docs(m5): state doc, runbook, roadmap amendment, repo state"
```

Confirm `docs/setup/m5-infra-state.local.md` exists locally, is filled in, and is NOT staged (`git status` must not list it; the `docs/setup/*.local.md` gitignore rule covers it).

---

## Done means

- `tools/secrets/test.sh` passes; shellcheck clean.
- `terraform fmt -check`, `validate`, `test` pass in `infra/aws/`.
- Live posture: hop limit 1, `/srv/secrets` 700 platform from bootstrap, Env-files 600.
- `https://hello.wingkongexchange.dev/` serves the updated SSM `MESSAGE`.
- Docs committed; no real identifiers in any committed file.
- Milestone close (outer flow, not this plan): whole-branch review, `/security-review`, ff merge after user review, PROGRESS.md overwrite.
