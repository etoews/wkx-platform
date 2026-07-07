# M4: Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every log a Service or the Host produces lands in CloudWatch under `/wkx/`, host metrics flow to `CWAgent`, one dashboard shows vital signs plus per-service request rate, and five host alarms email via SNS.

**Architecture:** The Docker daemon ships container logs straight to per-service log groups via the `awslogs` driver, configured in cloud-only `compose.cloud.yml` overlays (ADR 0020). The CloudWatch agent stays a GPG-verified host deb (ADR 0021) configured from SSM Parameter Store, handling only syslog and host metrics. A metric filter derives per-service request rate from Caddy's named JSON access logger. Everything is specified in `docs/superpowers/specs/2026-07-06-m4-observability-design.md`.

**Tech Stack:** Terraform (aws root), CloudWatch Logs/Metrics/Alarms/Dashboards, SNS, Docker `awslogs` driver + Compose overlays, CloudWatch agent deb, Caddy 2.11 access logging, SSM Session Manager.

## Global Constraints

- `env` is always explicit, never defaulted. All M4 resources are prod (`/wkx/<service>/prod`).
- No SSH; all box access via `aws ssm start-session` (ADR 0003).
- Committed files never carry real account state (invariant 7): the alert email lives in gitignored `infra/aws/terraform.local.tfvars`; real IDs and addresses go in `*.local.*` files only.
- Terraform: `terraform fmt -check`, `terraform validate`, and `terraform test` must pass before every apply. From Task 4 on, every aws-root plan/apply/test needs `-var-file=terraform.local.tfvars` (test: use the `variables` blocks added in Task 4).
- ADR 0017: any `host/cloud-init.yaml` change replaces the Host. Task 6 does this deliberately, once. Task 7's redeploy must follow it.
- No billing alarm anywhere in this plan: the wallet guard is the `wkx-org-monthly` budget in `infra/mgmt/` (M4 grill decision).
- Metrics namespace stays `CWAgent` (IAM condition pinned in M2); log groups are created only by Terraform (`awslogs-create-group: "false"`).
- Prose in NZ English, no em dashes. Diagrams in mermaid.
- Commit style: `infra(m4):`, `feat(m4):`, `docs(m4):`. Work on the existing `feat/m4-observability` branch.
- The two hands-on artefacts that define done: tail Caddy and hello logs in the CloudWatch console; force a host alarm into ALARM and receive the email.

---

### Task 1: Gates on the running Host (read-only)

**Files:**
- None changed (verification task)

**Interfaces:**
- Produces: `<IFACE>`, the Host's primary network interface name (expected `ens5`), used verbatim in Task 3's agent config and Task 9's network widget; confirmation that `gpg` exists on the AMI (Task 6's script assumes it).

- [ ] **Step 1: Identify the primary interface and check gpg**

```bash
aws ssm start-session --target "$(cd infra/aws && terraform output -raw instance_id)"
```

In the session:

```bash
ip -o -4 addr show scope global   # the interface holding the private IP
command -v gpg && gpg --version | head -1
```

Expected: one interface (expected name `ens5`; if it differs, use the observed name wherever this plan says `ens5`); `gpg` present (Ubuntu server preinstalls it). If gpg is absent, add `gnupg` to the `packages:` list in Task 6's cloud-init edit.

- [ ] **Step 2: Confirm the starting state**

Still in the session:

```bash
amazon-cloudwatch-agent-ctl -a status 2>/dev/null || echo "agent installed but never configured"
```

From the laptop:

```bash
aws logs describe-log-groups --log-group-name-prefix /wkx/ --query 'logGroups[].logGroupName'
```

Expected: agent status `stopped` (or the fallback message); no `/wkx/` log groups exist yet. No commit for this task.

---

### Task 2: Log groups + request-rate metric filter

**Files:**
- Create: `infra/aws/logs.tf`
- Create: `infra/aws/tests/observability_invariants.tftest.hcl`
- Modify: `infra/aws/iam.tf:52-54` (comment only)

**Interfaces:**
- Consumes: existing aws root (provider `default_tags`).
- Produces: log groups `/wkx/hello/prod`, `/wkx/caddy/prod`, `/wkx/platform/prod` (Tasks 3, 5, 6, 7 write to them); metric `RequestCount` in namespace `WKX/Edge` with dimension `Host` (Task 9's request widget reads it).

- [ ] **Step 1: Write the failing invariant tests**

`infra/aws/tests/observability_invariants.tftest.hcl`:

```hcl
# Observability invariants (M4): Terraform owns every /wkx log group, each
# with explicit retention (a group created any other way would be untagged
# and never-expiring), and the request-rate pipeline publishes to WKX/Edge.
run "log_groups_named_tagged_retained" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.name == "/wkx/hello/prod",
      aws_cloudwatch_log_group.caddy.name == "/wkx/caddy/prod",
      aws_cloudwatch_log_group.platform.name == "/wkx/platform/prod",
    ])
    error_message = "Log groups follow /wkx/<service>/<env>."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.retention_in_days == 7,
      aws_cloudwatch_log_group.caddy.retention_in_days == 30,
      aws_cloudwatch_log_group.platform.retention_in_days == 7,
    ])
    error_message = "Tiered retention: 7d app and platform, 30d Caddy access logs."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.tags["Service"] == "hello",
      aws_cloudwatch_log_group.caddy.tags["Service"] == "caddy",
      !contains(keys(aws_cloudwatch_log_group.platform.tags), "Service"),
      aws_cloudwatch_log_group.hello.tags["Env"] == "prod",
      aws_cloudwatch_log_group.caddy.tags["Env"] == "prod",
      aws_cloudwatch_log_group.platform.tags["Env"] == "prod",
    ])
    error_message = "Per-service groups carry Service; the platform group omits it."
  }
}

run "request_rate_metric_filter" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.edge_requests.pattern == "{ $.logger = \"http.log.access.wkx\" }"
    error_message = "Filter must exact-match the named Caddy access logger."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].namespace == "WKX/Edge",
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].name == "RequestCount",
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].dimensions["Host"] == "$.request.host",
    ])
    error_message = "RequestCount publishes to WKX/Edge with the Host dimension."
  }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd infra/aws && terraform test -filter=tests/observability_invariants.tftest.hcl
```

Expected: FAIL, references to undeclared resources `aws_cloudwatch_log_group.*`.

- [ ] **Step 3: Write `infra/aws/logs.tf`**

```hcl
# One log group per service (naming table, design spec §6); Terraform owns
# creation so every group is tagged and retention-bounded. The awslogs
# driver and the CloudWatch agent only ever write (iam.tf).
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/wkx/hello/prod"
  retention_in_days = 7

  tags = { Name = "/wkx/hello/prod", Service = "hello", Env = "prod" }
}

resource "aws_cloudwatch_log_group" "caddy" {
  # 30 days, not 7: access logs feed the request-rate metric and answer
  # traffic questions after the fact.
  name              = "/wkx/caddy/prod"
  retention_in_days = 30

  tags = { Name = "/wkx/caddy/prod", Service = "caddy", Env = "prod" }
}

resource "aws_cloudwatch_log_group" "platform" {
  # Host-level emissions: platform occupies the service slot (CONTEXT.md);
  # no Service tag, per the tagging strategy's shared/platform category.
  name              = "/wkx/platform/prod"
  retention_in_days = 7

  tags = { Name = "/wkx/platform/prod", Env = "prod" }
}

# Request rate from Caddy access logs, derived server-side. Exact logger
# match: the Caddyfile names its access logger wkx because auto-generated
# names (log0, log1) shift if site blocks reorder. Each distinct Host value
# is one custom metric; bounded, because only hostnames with proxied zone
# records reach the origin.
resource "aws_cloudwatch_log_metric_filter" "edge_requests" {
  name           = "wkx-edge-requests"
  log_group_name = aws_cloudwatch_log_group.caddy.name
  pattern        = "{ $.logger = \"http.log.access.wkx\" }"

  metric_transformation {
    name      = "RequestCount"
    namespace = "WKX/Edge"
    value     = "1"

    dimensions = {
      Host = "$.request.host"
    }
  }
}
```

In `infra/aws/iam.tf`, replace the comment above `resource "aws_iam_role_policy" "cloudwatch_write"`:

```hcl
# Log groups themselves are created by Terraform in M4; the box only writes.
# PutMetricData is pinned to the CloudWatch agent's default namespace; M4
# adjusts the condition if it renames the namespace.
```

with:

```hcl
# Log groups are created by Terraform (logs.tf); the box only writes.
# PutMetricData stays pinned to the agent's default CWAgent namespace,
# which M4 kept.
```

- [ ] **Step 4: Verify tests pass, then apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform apply
```

Expected: all test runs PASS; apply adds exactly 4 resources.

- [ ] **Step 5: Verify live and commit**

```bash
aws logs describe-log-groups --log-group-name-prefix /wkx/ \
  --query 'logGroups[].{name:logGroupName,retention:retentionInDays}' --output table
git add infra/aws/logs.tf infra/aws/tests/observability_invariants.tftest.hcl infra/aws/iam.tf
git commit -m "infra(m4): log groups and request-rate metric filter"
```

Expected: three groups with retention 7 / 30 / 7.

---

### Task 3: Agent config file + SSM parameter

**Files:**
- Create: `host/cloudwatch-agent.json`
- Create: `infra/aws/cloudwatch_agent.tf`
- Modify: `infra/aws/tests/observability_invariants.tftest.hcl`

**Interfaces:**
- Consumes: `<IFACE>` from Task 1 (written below as `ens5`); log group `/wkx/platform/prod` (Task 2).
- Produces: SSM parameter `/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG` (Task 6's cloud-init fetches it; the resource name `aws_ssm_parameter.cloudwatch_agent_config` is referenced by Task 6's `ec2.tf` edit); six `CWAgent` custom metrics once the agent runs.

- [ ] **Step 1: Write `host/cloudwatch-agent.json`**

Cardinality is pinned everywhere: aggregate CPU only, two named mount points with `drop_device` (Nitro device names churn across reboots and would break alarms), one named interface, `InstanceId` as the only appended dimension. Net result: six custom metrics. JSON allows no comments; this paragraph is the record.

```json
{
  "agent": {
    "metrics_collection_interval": 60
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/wkx/platform/prod",
            "log_stream_name": "syslog"
          }
        ]
      }
    }
  },
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu": {
        "totalcpu": true,
        "measurement": ["usage_active"]
      },
      "mem": {
        "measurement": ["used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/srv/data"],
        "drop_device": true
      },
      "net": {
        "measurement": ["bytes_sent", "bytes_recv"],
        "resources": ["ens5"]
      }
    }
  }
}
```

Syntax check:

```bash
python3 -m json.tool host/cloudwatch-agent.json >/dev/null && echo valid
```

Expected: `valid`.

- [ ] **Step 2: Write the failing test**

Append to `infra/aws/tests/observability_invariants.tftest.hcl`:

```hcl
run "agent_config_from_repo_file" {
  command = plan

  assert {
    condition = alltrue([
      aws_ssm_parameter.cloudwatch_agent_config.name == "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG",
      aws_ssm_parameter.cloudwatch_agent_config.type == "String",
    ])
    error_message = "Agent config: /wkx/platform path, plain String (not a secret)."
  }

  assert {
    condition     = nonsensitive(aws_ssm_parameter.cloudwatch_agent_config.value) == file("../../host/cloudwatch-agent.json")
    error_message = "The parameter value must be exactly the repo file."
  }
}
```

```bash
cd infra/aws && terraform test -filter=tests/observability_invariants.tftest.hcl
```

Expected: FAIL, undeclared resource `aws_ssm_parameter.cloudwatch_agent_config`.

- [ ] **Step 3: Write `infra/aws/cloudwatch_agent.tf`**

```hcl
# The agent's config travels through SSM Parameter Store: the repo file is
# the source of truth, Terraform publishes it, the Host fetches it at boot
# (cloud-init) or on demand via SSM RunCommand. Config changes therefore
# never replace the Host; ADR 0017 applies only to cloud-init edits.
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG"
  type  = "String"
  value = file("${path.module}/../../host/cloudwatch-agent.json")

  tags = {
    Name = "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG"
    Env  = "prod"
  }
}
```

- [ ] **Step 4: Verify tests pass, then apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform apply
```

Expected: all runs PASS; apply adds exactly 1 resource.

- [ ] **Step 5: Verify live and commit**

```bash
aws ssm get-parameter --name /wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG \
  --query 'Parameter.{name:Name,type:Type}' --output table
git add host/cloudwatch-agent.json infra/aws/cloudwatch_agent.tf infra/aws/tests/observability_invariants.tftest.hcl
git commit -m "infra(m4): CloudWatch agent config published to SSM"
```

Expected: the parameter exists, type `String`.

---

### Task 4: SNS topic + alert_email

**Files:**
- Create: `infra/aws/sns.tf`
- Create: `infra/aws/terraform.tfvars.example`
- Modify: `infra/aws/variables.tf`
- Modify: `infra/aws/tests/observability_invariants.tftest.hcl`
- Modify: `infra/aws/tests/ecr_invariants.tftest.hcl` (variables block only)
- Modify: `infra/aws/tests/host_invariants.tftest.hcl` (variables block only)
- Modify: `infra/aws/tests/security_invariants.tftest.hcl` (variables block only)

**Interfaces:**
- Consumes: nothing new.
- Produces: `aws_sns_topic.alerts` (Task 8's alarms reference `aws_sns_topic.alerts.arn`); variable `alert_email` (no default); a confirmed email subscription.

- [ ] **Step 1: Add the variable and the example tfvars**

Append to `infra/aws/variables.tf`:

```hcl
variable "alert_email" {
  description = "Email address for alarm notifications. Real value lives in the gitignored terraform.local.tfvars (invariant 7); same variable name and pattern as infra/mgmt."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a plausible email address."
  }
}
```

Create `infra/aws/terraform.tfvars.example`:

```hcl
# Copy to terraform.local.tfvars (gitignored) and fill in the real value.
# From here on, plan/apply with: terraform apply -var-file=terraform.local.tfvars
alert_email = "you@example.com"
```

Then create the real file and confirm it is ignored:

```bash
cp infra/aws/terraform.tfvars.example infra/aws/terraform.local.tfvars
# edit infra/aws/terraform.local.tfvars: set the real alert address
git check-ignore infra/aws/terraform.local.tfvars && echo ignored
```

Expected: `ignored`. If not, stop; fix `infra/.gitignore` before writing the real address.

- [ ] **Step 2: Give every test file the variable**

A no-default variable breaks `terraform test` for every existing file. At the top of each of `tests/ecr_invariants.tftest.hcl`, `tests/host_invariants.tftest.hcl`, `tests/security_invariants.tftest.hcl`, and `tests/observability_invariants.tftest.hcl`, add:

```hcl
variables {
  alert_email = "alerts@example.invalid"
}
```

- [ ] **Step 3: Write the failing test**

Append to `infra/aws/tests/observability_invariants.tftest.hcl`:

```hcl
run "alerts_topic" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "wkx-alerts"
    error_message = "The notification topic is wkx-alerts."
  }

  assert {
    condition     = aws_sns_topic_subscription.alerts_email.protocol == "email"
    error_message = "wkx-alerts must have an email subscription."
  }
}
```

```bash
cd infra/aws && terraform test -filter=tests/observability_invariants.tftest.hcl
```

Expected: FAIL, undeclared resource `aws_sns_topic.alerts`.

- [ ] **Step 4: Write `infra/aws/sns.tf`**

```hcl
# One notification channel for every host alarm. Email is the only
# subscriber; the address never appears in committed files (invariant 7).
resource "aws_sns_topic" "alerts" {
  name = "wkx-alerts"

  tags = { Name = "wkx-alerts" }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
```

- [ ] **Step 5: Verify tests pass, then apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform apply -var-file=terraform.local.tfvars
```

Expected: all runs PASS; apply adds exactly 2 resources.

- [ ] **Step 6: Confirm the subscription, verify, commit**

Click the confirmation link in the "AWS Notification - Subscription Confirmation" email, then:

```bash
TOPIC_ARN=$(aws sns list-topics \
  --query 'Topics[?contains(TopicArn, `wkx-alerts`)].TopicArn' --output text)
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query 'Subscriptions[0].SubscriptionArn' --output text
git add infra/aws/sns.tf infra/aws/variables.tf infra/aws/terraform.tfvars.example infra/aws/tests/
git commit -m "infra(m4): wkx-alerts SNS topic; alert_email via local tfvars"
```

Expected: a full subscription ARN, not `PendingConfirmation`.

---

### Task 5: Compose overlays + named Caddy access logger

**Files:**
- Create: `platform/compose.cloud.yml`
- Create: `hello/compose.cloud.yml`
- Modify: `platform/Caddyfile`
- Modify: `platform/compose.yml` (header comment)
- Modify: `hello/compose.yml` (header comment)

**Interfaces:**
- Consumes: log groups (Task 2); the deployed Caddy image sha (from `docs/setup/m3-infra-state.local.md`).
- Produces: the cloud deploy commands Task 7 runs (`docker compose -f compose.yml -f compose.cloud.yml ...`); access-log lines with `"logger":"http.log.access.wkx"` that Task 2's filter matches.

- [ ] **Step 1: Write `platform/compose.cloud.yml`**

```yaml
# Cloud overlay (ADR 0020): container logs ship to CloudWatch via the
# awslogs driver, authenticated by the instance role. Dual logging keeps
# `docker logs` working. The home server (M9) never applies this file.
# Run as: docker compose -f compose.yml -f compose.cloud.yml -p platform-prod up -d
services:
  caddy:
    logging:
      driver: awslogs
      options:
        awslogs-region: ap-southeast-2
        awslogs-group: /wkx/caddy/prod
        awslogs-create-group: "false"
        tag: "{{.Name}}"
        mode: non-blocking
        max-buffer-size: "4m"
```

- [ ] **Step 2: Write `hello/compose.cloud.yml`**

```yaml
# Cloud overlay (ADR 0020): see platform/compose.cloud.yml. Part of the
# platform contract from M8's reference project on.
# Run as: ENV=prod docker compose -f compose.yml -f compose.cloud.yml -p hello-prod up -d
services:
  web:
    logging:
      driver: awslogs
      options:
        awslogs-region: ap-southeast-2
        awslogs-group: /wkx/hello/prod
        awslogs-create-group: "false"
        tag: "{{.Name}}"
        mode: non-blocking
        max-buffer-size: "4m"
```

- [ ] **Step 3: Gate: verify the merged logging stanza renders (spec §8)**

```bash
cd platform && ECR_REGISTRY=example.invalid CADDY_TAG=check \
  docker compose -f compose.yml -f compose.cloud.yml -p check config | grep -A8 'logging:'
cd ../hello && ECR_REGISTRY=example.invalid HELLO_TAG=check ENV=check \
  docker compose -f compose.yml -f compose.cloud.yml -p check config | grep -A8 'logging:'
cd ..
```

Expected, in both outputs: `driver: awslogs` plus all five options exactly as written. If the stanza is missing or mangled, stop; the overlay merge is broken.

- [ ] **Step 4: Add the named access logger to `platform/Caddyfile`**

The wildcard site block becomes:

```caddyfile
*.wingkongexchange.dev {
	tls {
		dns cloudflare {env.CLOUDFLARE_API_TOKEN}
	}
	# Access logs (M4): a named logger, so the metric filter exact-matches
	# http.log.access.wkx (auto-generated names like log0 shift if site
	# blocks reorder). JSON to stdout rides the awslogs pipeline; Caddy's
	# runtime logs stay on stderr. One logger here covers the imported
	# snippet hosts and the 404 fallthrough (verified on v2.11.4).
	log wkx {
		output stdout
		format json
	}
	# Subdomains with no snippet fall through to here.
	respond 404
}

import /etc/caddy/Caddyfile.d/*.caddy
```

- [ ] **Step 5: Validate the Caddyfile with the deployed image**

```bash
CADDY_REPO=$(cd infra/aws && terraform output -raw caddy_ecr_repository_url)
CADDY_SHA=<caddy sha from docs/setup/m3-infra-state.local.md>
aws ecr get-login-password --region ap-southeast-2 \
  | docker login --username AWS --password-stdin "${CADDY_REPO%%/*}"
docker run --rm --platform linux/arm64 \
  -v "$PWD/platform/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -e CLOUDFLARE_API_TOKEN=validate-only \
  "$CADDY_REPO:$CADDY_SHA" caddy validate --config /etc/caddy/Caddyfile
```

Expected: `Valid configuration`.

- [ ] **Step 6: Update the run-command header comments**

In `platform/compose.yml`, change the header line `# Run as: docker compose -p platform-prod up -d` to:

```yaml
# Run as: docker compose -f compose.yml -f compose.cloud.yml -p platform-prod up -d
# (cloud; the home server omits the overlay, ADR 0020)
```

In `hello/compose.yml`, change `# Run as: ENV=prod docker compose -p hello-prod up -d  (env always explicit)` to:

```yaml
# Run as: ENV=prod docker compose -f compose.yml -f compose.cloud.yml -p hello-prod up -d
# (env always explicit; cloud applies the awslogs overlay, home omits it)
```

- [ ] **Step 7: Commit**

```bash
git add platform/compose.cloud.yml hello/compose.cloud.yml platform/Caddyfile platform/compose.yml hello/compose.yml
git commit -m "feat(m4): awslogs overlays; named Caddy access logger wkx"
```

---

### Task 6: GPG-verified agent install via cloud-init (one Host replacement)

**Files:**
- Modify: `host/cloud-init.yaml`
- Modify: `infra/aws/ec2.tf:36-38` (user_data templatefile arguments)

**Interfaces:**
- Consumes: `aws_ssm_parameter.cloudwatch_agent_config` (Task 3).
- Produces: a replacement Host running a GPG-verified agent that ships syslog to `/wkx/platform/prod` and six metrics to `CWAgent`; the observed metric dimension sets Task 8's alarms and Task 9's widgets key on.

- [ ] **Step 1: Add the install script to `host/cloud-init.yaml`**

Append to `write_files:` (after the `wkx-mount-data` entry). Plain `$var` shell syntax is deliberate: `templatefile()` only interpolates `${...}`, and the one `${agent_config_param}` below is exactly that.

```yaml
  - path: /usr/local/bin/wkx-install-cwagent
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      # GPG-verified CloudWatch agent install (M4). Key URL and fingerprint
      # come from the agent's package-signature docs; any mismatch aborts
      # bootstrap loudly rather than installing anyway.
      set -euo pipefail
      KEY_URL='https://amazoncloudwatch-agent.s3.amazonaws.com/assets/amazon-cloudwatch-agent.gpg'
      DEB_URL='https://amazoncloudwatch-agent-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb'
      EXPECTED_FPR='937616F3450B7D806CBD9725D58167303B789C72'

      workdir=$(mktemp -d)
      trap 'rm -rf "$workdir"' EXIT
      export GNUPGHOME="$workdir/gnupg"
      mkdir -m 700 "$GNUPGHOME"

      curl -fsSL -o "$workdir/agent.gpg" "$KEY_URL"
      gpg --import "$workdir/agent.gpg"
      fpr=$(gpg --with-colons --fingerprint | awk -F: '$1 == "fpr" { print $10; exit }')
      if [ "$fpr" != "$EXPECTED_FPR" ]; then
        echo "wkx-install-cwagent: key fingerprint mismatch: $fpr" >&2
        exit 1
      fi

      curl -fsSL -o "$workdir/agent.deb" "$DEB_URL"
      curl -fsSL -o "$workdir/agent.deb.sig" "$DEB_URL.sig"
      gpg --verify "$workdir/agent.deb.sig" "$workdir/agent.deb"
      dpkg -i "$workdir/agent.deb"
```

- [ ] **Step 2: Replace the unverified install in `runcmd:`**

Delete these three lines:

```yaml
  - curl -fsSL -o /tmp/amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
  - dpkg -i /tmp/amazon-cloudwatch-agent.deb
  - rm -f /tmp/amazon-cloudwatch-agent.deb
```

In their place:

```yaml
  - [/usr/local/bin/wkx-install-cwagent]
  # Agent config comes from SSM (M4): the same apply that replaces the Host
  # publishes the parameter. -s starts the agent and enables its systemd
  # unit, so it survives reboots. The leading slash is required for
  # hierarchical parameter names.
  - [/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl, -a, fetch-config, -m, ec2, -c, 'ssm:${agent_config_param}', -s]
```

Update the file's header comment: the template now has two variables. Replace `the only template variable is data_volume_device.` with `template variables: data_volume_device, agent_config_param.` and append a line `# M4 added: GPG-verified CloudWatch agent install, configured from SSM.`

- [ ] **Step 3: Pass the parameter name into the template**

In `infra/aws/ec2.tf`, the `user_data` argument becomes:

```hcl
  user_data = templatefile("${path.module}/../../host/cloud-init.yaml", {
    data_volume_device = local.data_volume_device
    agent_config_param = aws_ssm_parameter.cloudwatch_agent_config.name
  })
```

(This reference also orders the apply: the parameter exists before the replacement Host boots.)

- [ ] **Step 4: Validate, plan, expect one replacement, apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform plan -var-file=terraform.local.tfvars
```

Expected plan: `aws_instance.host` **replaced** (user_data change), `aws_eip_association` and `aws_volume_attachment` replaced with it, the Data volume and log groups untouched.

```bash
terraform apply -var-file=terraform.local.tfvars
```

- [ ] **Step 5: Verify the GPG install and the running agent**

```bash
aws ssm start-session --target "$(cd infra/aws && terraform output -raw instance_id)"
```

On the box:

```bash
sudo grep 'Good signature' /var/log/cloud-init-output.log   # the .sig verified
amazon-cloudwatch-agent-ctl -a status                        # "status": "running"
df -h /srv/data                                              # Data volume remounted
```

From the laptop (allow two to three minutes for first datapoints):

```bash
aws logs tail /wkx/platform/prod --since 10m | head -5
aws cloudwatch list-metrics --namespace CWAgent \
  --query 'Metrics[].{name:MetricName,dims:Dimensions}' --output json
```

Expected: syslog lines in the tail; exactly six metrics. **Record the dimension sets** (gate for Tasks 8 and 9): expected `cpu_usage_active` `{InstanceId, cpu: cpu-total}`, `mem_used_percent` `{InstanceId}`, `disk_used_percent` `{InstanceId, path, fstype}` twice, `net_bytes_sent`/`net_bytes_recv` `{InstanceId, interface}`. If the observed sets differ, Tasks 8 and 9 use the observed sets verbatim. If more than six metrics appear, the config leaked cardinality; fix `host/cloudwatch-agent.json`, re-apply (parameter change only), and re-fetch via `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c ssm:/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG -s` on the box: no Host replacement.

- [ ] **Step 6: Commit**

```bash
git add host/cloud-init.yaml infra/aws/ec2.tf
git commit -m "infra(m4): GPG-verified agent install; config fetched from SSM (Host replaced, ADR 0017)"
```

---

### Task 7: On-box redeploy with the overlays

**Files:**
- None committed (documented procedure; results recorded in Task 10's state doc)

**Interfaces:**
- Consumes: the replacement Host (Task 6), the overlays and Caddyfile (Task 5), the M3 images (unchanged; shas in `docs/setup/m3-infra-state.local.md`).
- Produces: a serving origin whose container logs flow to CloudWatch; the access-log evidence Task 2's filter needs; the on-box layout every later deploy assumes.

- [ ] **Step 1: One-time root setup, then become the platform user**

```bash
aws ssm start-session --target "$(cd infra/aws && terraform output -raw instance_id)"
```

In the session:

```bash
sudo mkdir -p /etc/caddy/Caddyfile.d /srv/secrets/caddy
sudo chown -R platform:platform /etc/caddy/Caddyfile.d /srv/secrets
sudo -iu platform
```

- [ ] **Step 2: Clone the repo on the milestone branch; render secrets**

```bash
git clone https://github.com/etoews/wkx-platform.git ~/wkx-platform
cd ~/wkx-platform && git checkout feat/m4-observability
umask 077
printf 'CLOUDFLARE_API_TOKEN=%s\n' \
  "$(aws ssm get-parameter --name /wkx/caddy/prod/CLOUDFLARE_API_TOKEN \
      --with-decryption --query Parameter.Value --output text \
      --region ap-southeast-2)" > /srv/secrets/caddy/prod.env
```

- [ ] **Step 3: Write the on-box .env files and log in to ECR**

Use the shas from `docs/setup/m3-infra-state.local.md` (images unchanged in M4):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.ap-southeast-2.amazonaws.com"
printf 'ECR_REGISTRY=%s\nCADDY_TAG=%s\n' "$ECR_REGISTRY" "<caddy sha>" \
  > ~/wkx-platform/platform/.env
printf 'ECR_REGISTRY=%s\nHELLO_TAG=%s\nENV=prod\n' "$ECR_REGISTRY" "<hello sha>" \
  > ~/wkx-platform/hello/.env
aws ecr get-login-password --region ap-southeast-2 \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
```

- [ ] **Step 4: Start both stacks WITH the overlays; drop the snippet**

```bash
cd ~/wkx-platform/platform
docker compose -f compose.yml -f compose.cloud.yml -p platform-prod up -d
cd ~/wkx-platform/hello
docker compose -f compose.yml -f compose.cloud.yml -p hello-prod up -d

printf 'hello.wingkongexchange.dev {\n\treverse_proxy hello-prod:8000\n}\n' \
  > /etc/caddy/Caddyfile.d/hello-prod.caddy
cd ~/wkx-platform/platform
docker compose -p platform-prod exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Expected: both stacks up; reload exits 0. The wildcard certificate is NOT re-issued (Caddy's data dir is on the Data volume).

- [ ] **Step 5: Verify serving and dual logging**

From the laptop:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://hello.wingkongexchange.dev   # 200
```

On the box:

```bash
docker logs --tail 3 platform-prod-caddy-1   # dual logging: readable despite awslogs
docker logs --tail 3 hello-prod-web-1
```

Expected: 200; both `docker logs` calls print lines (the local read cache works).

- [ ] **Step 6: Gate: access-log coverage (spec §8), and the first roadmap artefact**

From the laptop, generate one snippet-routed hit; on the box, one 404 fallthrough hit:

```bash
curl -s -o /dev/null https://hello.wingkongexchange.dev        # laptop
curl -sk -o /dev/null --resolve unrouted.wingkongexchange.dev:443:127.0.0.1 \
  https://unrouted.wingkongexchange.dev                        # on the box
```

Then from the laptop:

```bash
aws logs tail /wkx/caddy/prod --since 5m | grep -c 'http.log.access.wkx'
aws logs tail /wkx/caddy/prod --since 5m | grep 'unrouted'
aws logs tail /wkx/hello/prod --since 5m | head -3
```

Expected: access-log count ≥ 2; the unrouted 404 line present (the wildcard logger covers imported host blocks AND the fallthrough on the running version); hello stderr lines flowing. Also tail both groups in the CloudWatch console (roadmap artefact). **If the snippet-host or 404 lines are missing**, the wildcard-logger behaviour has regressed: stop, flag it, and fall back to a `log wkx` block per snippet (a platform-contract change to record in ADR 0018's orbit before continuing).

---

### Task 8: Host alarms

**Files:**
- Create: `infra/aws/alarms.tf`
- Modify: `infra/aws/tests/observability_invariants.tftest.hcl`

**Interfaces:**
- Consumes: `aws_sns_topic.alerts` (Task 4), `aws_instance.host.id` (existing), the observed dimension sets (Task 6 Step 5).
- Produces: five alarms named `wkx-host-*`; the forced-alarm hands-on artefact.

- [ ] **Step 1: Gate: confirm the dimension sets**

Use the Task 6 Step 5 record. The code below assumes the expected sets (`fstype` is `ext4` for both mounts, aggregate CPU carries `cpu: cpu-total`, interface is `ens5`). Where the record differs, use the observed values; an alarm whose dimensions match nothing sits permanently in INSUFFICIENT_DATA.

- [ ] **Step 2: Write the failing test**

Append to `infra/aws/tests/observability_invariants.tftest.hcl`:

> Execution note (2026-07-07): the alarm_actions asserts below proved unevaluable in a create-plan run ("Condition expression could not be evaluated"); the committed test pins the plan-time-knowable attributes instead, and SNS wiring was live-verified post-apply.

```hcl
run "alarms_wired_to_sns" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_cloudwatch_metric_alarm.disk_root.alarm_actions) > 0,
      length(aws_cloudwatch_metric_alarm.disk_data.alarm_actions) > 0,
      length(aws_cloudwatch_metric_alarm.mem.alarm_actions) > 0,
      length(aws_cloudwatch_metric_alarm.cpu.alarm_actions) > 0,
      length(aws_cloudwatch_metric_alarm.cpu_credits.alarm_actions) > 0,
    ])
    error_message = "Every alarm must notify wkx-alerts."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.cpu_credits.namespace == "AWS/EC2",
      aws_cloudwatch_metric_alarm.cpu_credits.comparison_operator == "LessThanThreshold",
    ])
    error_message = "The credit alarm reads AWS/EC2 CPUCreditBalance, alarming low."
  }
}
```

```bash
cd infra/aws && terraform test -filter=tests/observability_invariants.tftest.hcl
```

Expected: FAIL, undeclared resources `aws_cloudwatch_metric_alarm.*`.

- [ ] **Step 3: Write `infra/aws/alarms.tf`**

```hcl
# Host alarms (M4). CWAgent metrics carry InstanceId (agent
# append_dimensions) and the Host is cattle (ADR 0017), so every alarm keys
# on aws_instance.host.id: the apply that replaces the Host re-points the
# alarms in the same plan. No billing alarm: the wallet guard is the
# wkx-org-monthly budget in infra/mgmt (M4 grill decision).
locals {
  alarm_period = 300
  alarm_evals  = 3 # 3 x 5 min = 15 min sustained
}

resource "aws_cloudwatch_metric_alarm" "disk_root" {
  alarm_name          = "wkx-host-disk-root"
  alarm_description   = "Root volume above 80% for 15 min."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    path       = "/"
    fstype     = "ext4"
  }

  tags = { Name = "wkx-host-disk-root" }
}

resource "aws_cloudwatch_metric_alarm" "disk_data" {
  alarm_name          = "wkx-host-disk-data"
  alarm_description   = "Data volume above 80% for 15 min: SQLite writes and logs are at risk."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    path       = "/srv/data"
    fstype     = "ext4"
  }

  tags = { Name = "wkx-host-disk-data" }
}

resource "aws_cloudwatch_metric_alarm" "mem" {
  alarm_name          = "wkx-host-mem"
  alarm_description   = "Memory above 90% for 15 min."
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
  }

  tags = { Name = "wkx-host-mem" }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "wkx-host-cpu"
  alarm_description   = "CPU above 80% for 15 min: the credit bank is draining (standard mode)."
  namespace           = "CWAgent"
  metric_name         = "cpu_usage_active"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    cpu        = "cpu-total"
  }

  tags = { Name = "wkx-host-cpu" }
}

resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  alarm_name          = "wkx-host-cpu-credits"
  alarm_description   = "Credit bank under 25% (144 of 576): throttling to the 20%-per-vCPU baseline approaches."
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 144
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
  }

  tags = { Name = "wkx-host-cpu-credits" }
}
```

- [ ] **Step 4: Verify tests pass, then apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform apply -var-file=terraform.local.tfvars
```

Expected: all runs PASS; apply adds exactly 5 resources.

- [ ] **Step 5: Watch the alarms leave INSUFFICIENT_DATA**

```bash
sleep 900   # 15 min of datapoints
aws cloudwatch describe-alarms --alarm-name-prefix wkx-host \
  --query 'MetricAlarms[].{name:AlarmName,state:StateValue}' --output table
```

Expected: all five `OK`. Any alarm stuck in `INSUFFICIENT_DATA` after 20 minutes has a dimension mismatch: re-check against the Task 6 Step 5 record.

- [ ] **Step 6: The forced-alarm hands-on artefact, then commit**

```bash
aws cloudwatch set-alarm-state --alarm-name wkx-host-disk-root \
  --state-value ALARM --state-reason "M4 hands-on artefact"
```

Expected: an ALARM email arrives at the configured address within a minute or two; the alarm returns to OK on the next real datapoint (and an OK email follows, since ok_actions is wired).

```bash
git add infra/aws/alarms.tf infra/aws/tests/observability_invariants.tftest.hcl
git commit -m "infra(m4): five host alarms wired to wkx-alerts"
```

---

### Task 9: Dashboard

**Files:**
- Create: `infra/aws/dashboard.tf`
- Modify: `infra/aws/tests/observability_invariants.tftest.hcl`

**Interfaces:**
- Consumes: `CWAgent` metrics and their dimension sets (Task 6), `WKX/Edge` `RequestCount` (Tasks 2, 7), `aws_instance.host.id`.
- Produces: dashboard `wkx-prod`.

- [ ] **Step 1: Write the failing test**

Append to `infra/aws/tests/observability_invariants.tftest.hcl`:

```hcl
run "dashboard_exists" {
  command = plan

  assert {
    condition     = aws_cloudwatch_dashboard.wkx.dashboard_name == "wkx-prod"
    error_message = "The dashboard wkx-prod must exist."
  }
}
```

```bash
cd infra/aws && terraform test -filter=tests/observability_invariants.tftest.hcl
```

Expected: FAIL, undeclared resource `aws_cloudwatch_dashboard.wkx`.

- [ ] **Step 2: Write `infra/aws/dashboard.tf`**

```hcl
# One dashboard: the box's vital signs and the edge request rate. Metric
# widgets use the same dimension sets as the alarms. The request widget
# SEARCHes WKX/Edge so new services appear without a dashboard change, and
# FILLs zero-traffic gaps (dimensioned filter metrics emit no datapoint
# when idle).
resource "aws_cloudwatch_dashboard" "wkx" {
  dashboard_name = "wkx-prod"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "CPU and credit bank"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "cpu_usage_active", "InstanceId", aws_instance.host.id, "cpu", "cpu-total"],
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", aws_instance.host.id, { yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Memory"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.host.id],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "Disk used %"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.host.id, "path", "/", "fstype", "ext4"],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.host.id, "path", "/srv/data", "fstype", "ext4"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "Network bytes"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["CWAgent", "net_bytes_sent", "InstanceId", aws_instance.host.id, "interface", "ens5"],
            ["CWAgent", "net_bytes_recv", "InstanceId", aws_instance.host.id, "interface", "ens5"],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6,
        properties = {
          title  = "Requests (per service + total)"
          region = var.region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{WKX/Edge,Host} MetricName=\"RequestCount\"', 'Sum', 300)", label = "per service", id = "per_service" }],
            [{ expression = "SUM(FILL(per_service, 0))", label = "total", id = "total" }],
          ]
        }
      },
    ]
  })
}
```

(If Task 6 Step 5 recorded different dimension names or an interface other than `ens5`, mirror the observed values here, exactly as Task 8 did.)

- [ ] **Step 3: Verify tests pass, then apply**

```bash
cd infra/aws
terraform fmt -check && terraform validate && terraform test
terraform apply -var-file=terraform.local.tfvars
```

Expected: all runs PASS; apply adds exactly 1 resource.

- [ ] **Step 4: Gate: the request-rate widget moves; the metric count holds**

```bash
for i in $(seq 1 20); do curl -s -o /dev/null https://hello.wingkongexchange.dev; done
sleep 300
aws cloudwatch get-metric-statistics --namespace WKX/Edge --metric-name RequestCount \
  --dimensions Name=Host,Value=hello.wingkongexchange.dev \
  --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 --statistics Sum
aws cloudwatch list-metrics --namespace WKX/Edge --query 'Metrics[].Dimensions[].Value'
```

Expected: datapoints summing at least 20; the `WKX/Edge` Host values are only real zone hostnames (spec §8: six agent metrics plus one `RequestCount` per live hostname). Open the `wkx-prod` dashboard in the console: all five widgets render, the request widget shows the curl burst.

- [ ] **Step 5: Commit**

```bash
git add infra/aws/dashboard.tf infra/aws/tests/observability_invariants.tftest.hcl
git commit -m "infra(m4): wkx-prod dashboard"
```

---

### Task 10: Documentation

**Files:**
- Create: `docs/setup/m4-infra-state.md`
- Create: `docs/setup/m4-infra-state.local.md` (gitignored; verify before writing real values)
- Modify: `CLAUDE.md` (repository-state paragraph)

**Interfaces:**
- Consumes: verification evidence (Tasks 6-9), on-box procedure (Task 7).
- Produces: the milestone record; M5 picks up from these docs. (ROADMAP, the design spec §4, CONTEXT.md, and ADRs 0020/0021 were already updated during the M4 grill: no further edits there.)

- [ ] **Step 1: Write `docs/setup/m4-infra-state.md` (public-safe template)**

```markdown
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
```

- [ ] **Step 2: Write the `.local.md` sibling; confirm it is ignored first**

```bash
git check-ignore docs/setup/m4-infra-state.local.md && echo ignored
```

Expected: `ignored`. Then record the real dates, agent version (`amazon-cloudwatch-agent-ctl -a status` on the box), and interface name.

- [ ] **Step 3: Update CLAUDE.md repository state**

In the "Repository state" paragraph, extend the live list: M4 observability is live (log groups, alarms, dashboard in `infra/aws/`; agent config in `host/cloudwatch-agent.json`; `compose.cloud.yml` overlays beside each compose file). Keep the still-to-come list accurate (`tools/` from M5, `template/` at M8).

- [ ] **Step 4: Commit**

```bash
git add docs/setup/m4-infra-state.md CLAUDE.md
git commit -m "docs(m4): milestone complete; observability live"
git status   # confirm the .local.md file is NOT staged or listed
```

---

## Execution notes

- Task order is the dependency order. Task 6 (Host replacement) must complete before Task 7 (redeploy); Task 8's alarm dimensions and Task 9's widgets depend on Task 6 Step 5's recorded metric dimensions.
- Tasks 2, 3, 4, 6, 8, 9 touch live infrastructure: run applies attended.
- From Task 4 on, every aws-root plan/apply needs `-var-file=terraform.local.tfvars`.
- If any step's expected output does not match, stop and diagnose before the next step; never record a green state doc over a red check (superpowers:verification-before-completion).
