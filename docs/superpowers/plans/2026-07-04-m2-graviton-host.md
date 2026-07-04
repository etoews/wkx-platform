# M2: Graviton Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Host: a t4g.medium ARM64 Ubuntu 26.04 EC2 instance in the M1 public subnet, bootstrapped by cloud-init, reachable only through SSM, with an Elastic IP and a separate durable Data volume mounted at `/srv/data`, so that `aws ssm start-session` connects without SSH and `docker run hello-world` works on the box.

**Architecture:** All AWS resources extend the existing `infra/aws/` Terraform root (direct references to the M1 VPC, subnet, and security groups; one state). One new repo-root file, `host/cloud-init.yaml`, is rendered through `templatefile()` and becomes the instance user data. The Host is replaceable cattle (`user_data_replace_on_change = true`) while the Data volume is durable (`prevent_destroy`, clean detach) per ADR 0017. The design source of truth is `docs/superpowers/specs/2026-07-04-m2-graviton-host-design.md`.

**Tech Stack:** Terraform 1.15.1 · AWS provider `~> 5.0` (5.100.0 locked) · cloud-init (Ubuntu 26.04) · Docker Engine + Compose plugin from Docker's apt repo · AWS SSM Session Manager / RunCommand.

## Global Constraints

Every task implicitly inherits these. Values are copied verbatim from the M2 design spec, `CLAUDE.md`, and the ADRs.

- **Region:** `ap-southeast-2` (Sydney). Single region.
- **Existing root:** `infra/aws/` is already init-ed with `backend.local.hcl` (S3 backend, `use_lockfile`). Run all Terraform commands from `infra/aws/` unless stated otherwise.
- **No SSH, ever (ADR 0003):** no `key_name`, no port 22, no bastion. Access via SSM only.
- **Do not touch security group rules.** The M1 `web` (443 from Cloudflare prefix lists only, ADR 0004) and `host-egress` SGs are attached as-is.
- **ARM64 (ADR 0005):** t4g.medium, arm64 AMI, arm64 packages.
- **Tags:** provider `default_tags` already applies `Project=wkx`, `ManagedBy=terraform`, `Repo=wkx-platform`. Every M2 resource is host-level: add a `Name` tag, never `Env`/`Service`.
- **Invariant 7:** no real account state in committed files. The AWS account ID enters IAM policies only via `data.aws_caller_identity` at plan time; recorded values go in gitignored `docs/setup/m2-infra-state.local.md`.
- **Replaceable Host, durable Data volume (ADR 0017):** `user_data_replace_on_change = true`, `lifecycle { ignore_changes = [ami] }`, Data volume `prevent_destroy` with `stop_instance_before_detaching`.
- **Applies are gated:** the controller runs `terraform plan`, the user approves each plan, then the controller runs `terraform apply`. Task 5 starts the always-on spend (about USD $38/mo on-demand, accepted in spec §9).
- **templatefile hazard:** in `host/cloud-init.yaml`, `${...}` is Terraform interpolation. Embedded shell must never use `${VAR}` brace syntax; write `$VAR`. cloud-init's own `$KEY_FILE` and `$RELEASE` substitutions are brace-free and pass through safely.
- **Network commands** (Terraform against AWS, `aws` CLI, `curl`) need the sandbox disabled and a live SSO session (`aws sso login`, profile `wkx-platform`).
- **Writing conventions:** New Zealand English, no em dashes, mermaid for any diagram.

**Verified ground truth (checked live 2026-07-04):**

- SSM parameter `/aws/service/canonical/ubuntu/server/26.04/stable/current/arm64/hvm/ebs-gp3/ami-id` exists in ap-southeast-2 (resolved to `ami-0db668df0583aa213` on the day of writing; the value moves with Canonical's releases).
- Docker's apt repo serves the `resolute` (26.04) dist: `https://download.docker.com/linux/ubuntu/dists/resolute/Release` returns 200.
- CloudWatch agent arm64 deb URL returns 200: `https://amazoncloudwatch-agent-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb`.
- Provider 5.100.0 supports `user_data_replace_on_change`, `credit_specification`, `metadata_options`, and `stop_instance_before_detaching` (confirmed via `terraform providers schema -json`).

---

## File Structure

```
infra/aws/
├── ami.tf                             NEW  Canonical Ubuntu 26.04 arm64 AMI via SSM parameter
├── iam.tf                             NEW  wkx-host role, 3 inline policies, managed attachment, instance profile
├── ec2.tf                             NEW  aws_instance.host, aws_ebs_volume.data, aws_volume_attachment.data
├── eip.tf                             NEW  aws_eip.host + aws_eip_association.host
├── outputs.tf                         MOD  adds instance_id, host_public_ip, data_volume_id, instance_profile_name
└── tests/
    └── host_invariants.tftest.hcl     NEW  plan-time host invariants

host/
└── cloud-init.yaml                    NEW  Layer 2 bootstrap template (templatefile-rendered)

docs/setup/
├── m2-infra-state.md                  NEW  public-safe template
└── m2-infra-state.local.md            NEW  gitignored real values

ROADMAP.md                             MOD  M2 bullets: 26.04, backups grant deferred
CLAUDE.md                              MOD  repository-state paragraph
```

---

## Task 1: AMI data source

**Files:**
- Create: `infra/aws/ami.tf`

**Interfaces:**
- Produces: `data.aws_ssm_parameter.ubuntu_arm64` (its `.value` is the AMI ID, marked sensitive by the provider; Task 4 wraps it in `nonsensitive()`).

- [ ] **Step 1: Re-verify the parameter exists (live)**

```bash
aws ssm get-parameters \
  --names "/aws/service/canonical/ubuntu/server/26.04/stable/current/arm64/hvm/ebs-gp3/ami-id" \
  --region ap-southeast-2 \
  --query '{Ami:Parameters[0].Value,Invalid:InvalidParameters}'
```

Expected: `Ami` is an `ami-...` ID and `Invalid` is `[]`. If the parameter is missing, stop; the release token in the path is wrong and the spec's §4 assumption needs re-checking.

- [ ] **Step 2: Write `infra/aws/ami.tf`**

```hcl
# Canonical's published pointer to the latest stable Ubuntu 26.04 (Resolute)
# arm64 server AMI. Resolved at plan time; never hardcode an AMI ID. The
# instance ignores day-to-day drift of this value (see ec2.tf lifecycle):
# replacements pick up the then-current AMI, but a new AMI never causes a
# replacement by itself.
data "aws_ssm_parameter" "ubuntu_arm64" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}
```

- [ ] **Step 3: Format and validate**

```bash
cd infra/aws
terraform fmt
terraform validate
```

Expected: `fmt` makes no changes; `validate` prints "Success! The configuration is valid."

- [ ] **Step 4: Commit**

```bash
git add infra/aws/ami.tf
git commit -m "infra(m2): resolve Ubuntu 26.04 arm64 AMI via Canonical SSM parameter"
```

---

## Task 2: IAM role and instance profile

**Files:**
- Create: `infra/aws/iam.tf`

**Interfaces:**
- Consumes: `var.region` (exists in `infra/aws/variables.tf` from M1).
- Produces: `aws_iam_instance_profile.host` (name `wkx-host`; Task 4's instance references `.name`), `aws_iam_role.host`, `data.aws_caller_identity.current`.

- [ ] **Step 1: Write `infra/aws/iam.tf`**

Least privilege per spec §5: SSM core (managed), ECR pull-only, CloudWatch write scoped to `/wkx/*`, Parameter Store read scoped to `/wkx/*`. No S3 statement; the backups grant is deferred to M10 with the bucket itself.

```hcl
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "host" {
  name = "wkx-host"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "wkx-host" }
}

# SSM Session Manager + RunCommand agent permissions.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Pull-only ECR access. GetAuthorizationToken cannot be resource-scoped.
resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPullOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
    ]
  })
}

# Log groups themselves are created by Terraform in M4; the box only writes.
# PutMetricData is pinned to the CloudWatch agent's default namespace; M4
# adjusts the condition if it renames the namespace.
resource "aws_iam_role_policy" "cloudwatch_write" {
  name = "cloudwatch-write"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WkxLogGroupsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/wkx/*",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/wkx/*:*",
        ]
      },
      {
        Sid       = "CwAgentMetrics"
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "CWAgent" } }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ssm_params_read" {
  name = "ssm-params-read"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WkxParamsRead"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
      ]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/wkx/*"
    }]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "wkx-host"
  role = aws_iam_role.host.name

  tags = { Name = "wkx-host" }
}
```

- [ ] **Step 2: Format, validate, plan**

```bash
cd infra/aws
terraform fmt
terraform validate
terraform plan
```

Expected: `validate` succeeds. `plan` shows exactly 6 resources to add (role, managed-policy attachment, 3 inline policies, instance profile) and no changes to any M1 resource. Do not apply yet; Task 5 applies everything in one reviewed plan.

- [ ] **Step 3: Commit**

```bash
git add infra/aws/iam.tf
git commit -m "infra(m2): least-privilege wkx-host role and instance profile"
```

---

## Task 3: cloud-init bootstrap template

**Files:**
- Create: `host/cloud-init.yaml`

**Interfaces:**
- Consumes: one template variable, `data_volume_device` (a `/dev/disk/by-id/...` path string supplied by Task 4's `templatefile()` call).
- Produces: the rendered user data for `aws_instance.host`. Creates the `platform` user, installs Docker + Compose and the CloudWatch agent, and mounts the Data volume at `/srv/data`.

- [ ] **Step 1: Write `host/cloud-init.yaml`**

Reminder: `${data_volume_device}` is the only Terraform interpolation. All embedded shell uses brace-free `$VAR` syntax so `templatefile()` leaves it alone. `$KEY_FILE` and `$RELEASE` are cloud-init's own substitutions.

```yaml
#cloud-config
# Layer 2 bootstrap for the cloud Host. Rendered by Terraform templatefile();
# the only template variable is data_volume_device. Changing this file
# replaces the instance (ADR 0017): the Data volume, and therefore
# /srv/data, survives.

package_update: true
package_upgrade: true

apt:
  sources:
    docker.list:
      source: deb [arch=arm64 signed-by=$KEY_FILE] https://download.docker.com/linux/ubuntu $RELEASE stable
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

packages:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-buildx-plugin
  - docker-compose-plugin

users:
  - default
  - name: platform
    gecos: WKX platform user
    shell: /bin/bash
    lock_passwd: true
    # docker group membership is added in runcmd; the group only exists
    # once the docker-ce package has installed.

write_files:
  - path: /usr/local/bin/wkx-mount-data
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      # Idempotent format-if-blank + mount of the Data volume at /srv/data.
      # Safe to re-run; every step is a no-op when its work is already done.
      set -euo pipefail
      DEVICE='${data_volume_device}'

      # Terraform attaches the volume only after the instance reports
      # running, so poll rather than assume presence (up to 3 minutes).
      for i in $(seq 1 36); do
        if [ -e "$DEVICE" ]; then break; fi
        sleep 5
      done
      if [ ! -e "$DEVICE" ]; then
        echo "wkx-mount-data: $DEVICE never appeared" >&2
        exit 1
      fi

      # Format only when the device carries no filesystem (first boot ever).
      if ! blkid "$DEVICE" >/dev/null 2>&1; then
        mkfs.ext4 -L wkx-data "$DEVICE"
      fi

      mkdir -p /srv/data
      if ! grep -q '^LABEL=wkx-data ' /etc/fstab; then
        echo 'LABEL=wkx-data /srv/data ext4 defaults,nofail 0 2' >> /etc/fstab
      fi
      if ! mountpoint -q /srv/data; then
        mount /srv/data
      fi
      chown platform:platform /srv/data

runcmd:
  - [/usr/local/bin/wkx-mount-data]
  - [usermod, -aG, docker, platform]
  - [systemctl, enable, --now, docker]
  - [systemctl, enable, --now, snap.amazon-ssm-agent.amazon-ssm-agent.service]
  - curl -fsSL -o /tmp/amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
  - dpkg -i /tmp/amazon-cloudwatch-agent.deb
  - rm -f /tmp/amazon-cloudwatch-agent.deb
```

Notes for the implementer:

- The CloudWatch agent is installed but deliberately left unconfigured and not started; its config and start are M4 deliverables.
- The SSM agent ships preinstalled as a snap on Ubuntu server AMIs; the `systemctl enable --now` line is an assertion, not an installation.
- No `host/shared/` yet: extraction happens in M9 when `bootstrap.sh` gives it a second consumer.

- [ ] **Step 2: Sanity-check the YAML parses after substitution**

```bash
sed 's|${data_volume_device}|/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol0TEST|' host/cloud-init.yaml \
  | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin); print('YAML OK')"
```

Expected: `YAML OK`. (This catches indentation mistakes; full semantic validation happens on the box in Task 5 via `cloud-init status`.)

- [ ] **Step 3: Commit**

```bash
git add host/cloud-init.yaml
git commit -m "infra(m2): cloud-init bootstrap for the Host (docker, platform user, data volume)"
```

---

## Task 4: Host, Data volume, and EIP (test-first)

**Files:**
- Create: `infra/aws/tests/host_invariants.tftest.hcl`, `infra/aws/ec2.tf`, `infra/aws/eip.tf`
- Modify: `infra/aws/outputs.tf`

**Interfaces:**
- Consumes: `aws_subnet.public`, `aws_security_group.web`, `aws_security_group.host_egress` (M1), `data.aws_ssm_parameter.ubuntu_arm64` (Task 1), `aws_iam_instance_profile.host` (Task 2), `host/cloud-init.yaml` (Task 3).
- Produces: `aws_instance.host`, `aws_ebs_volume.data`, `aws_volume_attachment.data`, `aws_eip.host`, `aws_eip_association.host`; outputs `instance_id`, `host_public_ip`, `data_volume_id`, `instance_profile_name`.

- [ ] **Step 1: Write the failing invariant test `infra/aws/tests/host_invariants.tftest.hcl`**

```hcl
# Encodes the Host invariants as plan-time checks: keyless (ADR 0003),
# IMDSv2, standard CPU credits, encrypted gp3 volumes, and the
# replaceable-Host / durable-Data-volume stance (ADR 0017).
run "host_is_keyless_imdsv2_and_cattle" {
  command = plan

  assert {
    condition     = aws_instance.host.key_name == null
    error_message = "The Host must have no key pair. Access is SSM only (ADR 0003)."
  }

  assert {
    condition     = aws_instance.host.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required on the Host."
  }

  assert {
    condition     = aws_instance.host.credit_specification[0].cpu_credits == "standard"
    error_message = "CPU credits must be standard; unlimited can exceed the budget."
  }

  assert {
    condition     = aws_instance.host.user_data_replace_on_change == true
    error_message = "Bootstrap changes must replace the Host (ADR 0017)."
  }

  assert {
    condition = alltrue([
      aws_instance.host.root_block_device[0].encrypted,
      aws_instance.host.root_block_device[0].volume_type == "gp3",
    ])
    error_message = "The root volume must be encrypted gp3."
  }

  assert {
    condition = alltrue([
      aws_ebs_volume.data.encrypted,
      aws_ebs_volume.data.type == "gp3",
      aws_ebs_volume.data.size == 20,
    ])
    error_message = "The Data volume must be encrypted gp3, 20 GB."
  }

  assert {
    condition     = aws_volume_attachment.data.stop_instance_before_detaching == true
    error_message = "Detaching must stop the instance first for a clean unmount (ADR 0017)."
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd infra/aws
terraform test
```

Expected: FAIL with "Reference to undeclared resource" for `aws_instance.host` (the M1 `security_invariants` test still passes).

- [ ] **Step 3: Write `infra/aws/ec2.tf`**

```hcl
locals {
  # Stable /dev/disk/by-id symlink for the Data volume, derived from the
  # volume ID with the dash removed. The kernel's nvme names (/dev/nvme1n1)
  # and the attachment's /dev/sdf are both unstable; this symlink is not.
  data_volume_device = "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.data.id, "-", "")}"
}

# The Data volume: durable app data, independent of the instance lifecycle
# (ADR 0017). M10 snapshots target exactly this volume.
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = { Name = "wkx-host-data" }

  lifecycle {
    prevent_destroy = true
  }
}

# The Host: replaceable cattle (ADR 0017). A change to host/cloud-init.yaml
# replaces the instance; the EIP and Data volume carry over.
resource "aws_instance" "host" {
  ami           = nonsensitive(data.aws_ssm_parameter.ubuntu_arm64.value)
  instance_type = "t4g.medium"

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id, aws_security_group.host_egress.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  user_data = templatefile("${path.module}/../../host/cloud-init.yaml", {
    data_volume_device = local.data_volume_device
  })
  user_data_replace_on_change = true

  # standard, not the t4g default unlimited: an exhausted credit bank
  # throttles to baseline instead of buying surplus credits.
  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wkx-host" }

  lifecycle {
    # "current" in the SSM parameter moves with Canonical's releases; a new
    # AMI must never replace the Host by itself. Replacements (bootstrap
    # changes, taint) pick up the then-current AMI.
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.host.id

  # Replacement path: stop the instance, let the filesystem unmount
  # cleanly, then detach. Never force-detach a live volume (ADR 0017).
  stop_instance_before_detaching = true
}
```

- [ ] **Step 4: Write `infra/aws/eip.tf`**

```hcl
# Stable public IPv4 for the Host. M3's Cloudflare DNS records point here,
# so it must survive instance replacement; the association re-targets the
# replacement instance.
resource "aws_eip" "host" {
  domain = "vpc"
  tags   = { Name = "wkx-host" }
}

resource "aws_eip_association" "host" {
  allocation_id = aws_eip.host.id
  instance_id   = aws_instance.host.id
}
```

- [ ] **Step 5: Append outputs to `infra/aws/outputs.tf`**

```hcl
output "instance_id" {
  description = "EC2 instance ID of the Host (SSM session target)."
  value       = aws_instance.host.id
}

output "host_public_ip" {
  description = "Elastic IP attached to the Host (M3 DNS records target this)."
  value       = aws_eip.host.public_ip
}

output "data_volume_id" {
  description = "EBS volume ID of the Data volume (/srv/data)."
  value       = aws_ebs_volume.data.id
}

output "instance_profile_name" {
  description = "IAM instance profile attached to the Host."
  value       = aws_iam_instance_profile.host.name
}
```

- [ ] **Step 6: Format, validate, run the test to verify it passes**

```bash
cd infra/aws
terraform fmt
terraform validate
terraform test
```

Expected: `validate` succeeds; `terraform test` reports both test files passing (`2 passed, 0 failed`). The test needs live AWS credentials and network (it reads the AMI parameter and Cloudflare IP lists during its in-memory plan).

- [ ] **Step 7: Commit**

```bash
git add infra/aws/tests/host_invariants.tftest.hcl infra/aws/ec2.tf infra/aws/eip.tf infra/aws/outputs.tf
git commit -m "infra(m2): Host instance, durable data volume, EIP, and invariant tests"
```

---

## Task 5: Gated apply and cloud-side verification

**Files:** none (state-changing operations only).

**Interfaces:**
- Consumes: everything from Tasks 1 to 4.
- Produces: the live Host. This task starts the always-on spend (about USD $38/mo on-demand until M10's Savings Plan, accepted in spec §9).

- [ ] **Step 1: Full plan for user review**

```bash
cd infra/aws
terraform plan
```

Expected: 11 resources to add (6 IAM from Task 2, instance, Data volume, attachment, EIP, association), zero changes and zero destroys to M1 resources. **Stop and present this plan to the user for approval before applying.**

- [ ] **Step 2: Apply**

```bash
terraform apply
```

Expected: `Apply complete! Resources: 11 added, 0 changed, 0 destroyed.` Outputs show `instance_id`, `host_public_ip`, `data_volume_id`, `instance_profile_name`.

- [ ] **Step 3: Verify instance posture from the AWS side**

```bash
aws ec2 describe-instances --instance-ids "$(terraform output -raw instance_id)" \
  --query 'Reservations[0].Instances[0].{State:State.Name,Type:InstanceType,Key:KeyName,Imds:MetadataOptions.HttpTokens,Ip:PublicIpAddress,SGs:SecurityGroups[].GroupName}'
```

Expected: `State` is `running` (wait and re-run if `pending`), `Type` is `t4g.medium`, `Key` is `null`, `Imds` is `required`, `Ip` equals `terraform output -raw host_public_ip`, and `SGs` is exactly `["wkx-web", "wkx-host-egress"]`.

- [ ] **Step 4: Wait for cloud-init to finish (first boot takes minutes: apt upgrade + docker install)**

```bash
aws ssm send-command \
  --instance-ids "$(terraform output -raw instance_id)" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cloud-init status --wait --long"]' \
  --query 'Command.CommandId' --output text
```

Then poll the result (replace `<command-id>`):

```bash
aws ssm get-command-invocation \
  --command-id "<command-id>" \
  --instance-id "$(terraform output -raw instance_id)" \
  --query '{Status:Status,Out:StandardOutputContent,Err:StandardErrorContent}'
```

Expected: `Status` becomes `Success` and the output contains `status: done`. If SSM says the instance is not registered yet, wait a minute; the agent registers shortly after boot. If cloud-init reports `error`, read `/var/log/cloud-init-output.log` via another send-command before touching anything.

- [ ] **Step 5: Record real values in the gitignored local doc**

Create `docs/setup/m2-infra-state.local.md` with the actual `instance_id`, `host_public_ip`, `data_volume_id`, and the applied date. Do not commit it (the `docs/setup/*.local.md` gitignore rule from M0 covers it; confirm with `git status`).

---

## Task 6: Hands-on artefacts

**Files:** none (verification only).

**Why:** These are the M2 deliverables from `ROADMAP.md`: SSM session without SSH, working Docker, mounted Data volume.

- [ ] **Step 1: Scripted on-box verification via RunCommand**

```bash
cd infra/aws
aws ssm send-command \
  --instance-ids "$(terraform output -raw instance_id)" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker run --rm hello-world","df -h /srv/data","id platform","findmnt -no LABEL /srv/data","ss -tln | awk \"NR>1 {print \\$4}\""]' \
  --query 'Command.CommandId' --output text
```

Poll with `aws ssm get-command-invocation` as in Task 5 Step 4. Expected output contains:

- `Hello from Docker!` (engine works, arm64 image pulled through host-egress),
- a `/srv/data` line of roughly 20G on `/dev/nvme...` (the Data volume, not the root volume),
- `id platform` showing membership of the `docker` group,
- `wkx-data` from `findmnt` (mounted by label),
- no `:22` listener in the socket list.

- [ ] **Step 2: Interactive session (user-run artefact)**

Ask the user to run, in their own terminal (interactive; needs session-manager-plugin):

```bash
aws ssm start-session --target "$(cd infra/aws && terraform output -raw instance_id)"
```

Expected: a shell prompt as `ssm-user` on `wkx-host`, no SSH involved. `exit` ends the session.

---

## Task 7: Replacement drill

**Files:**
- Modify: `host/cloud-init.yaml` (one comment line)

**Why:** Proves ADR 0017 before M3 depends on it: a bootstrap change replaces the Host while the EIP and `/srv/data` survive.

- [ ] **Step 1: Write a marker file onto the Data volume**

```bash
cd infra/aws
aws ssm send-command \
  --instance-ids "$(terraform output -raw instance_id)" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo m2-replacement-drill > /srv/data/.replacement-drill","cat /srv/data/.replacement-drill"]' \
  --query 'Command.CommandId' --output text
```

Poll as before. Expected output: `m2-replacement-drill`. Also note the current values of `terraform output -raw instance_id` and `terraform output -raw host_public_ip`.

- [ ] **Step 2: Change the bootstrap and review the replacement plan**

Append this line to the header comment block of `host/cloud-init.yaml`:

```yaml
# Replacement drill exercised: 2026-07-04 (ADR 0017).
```

Then:

```bash
cd infra/aws
terraform plan
```

Expected: `aws_instance.host` is **replaced** (user data change), `aws_volume_attachment.data` and `aws_eip_association.host` are replaced, and `aws_ebs_volume.data` and `aws_eip.host` show **no changes**. **Stop and present this plan to the user for approval.**

- [ ] **Step 3: Apply and time it**

```bash
terraform apply
```

Expected: the attachment stops the instance before detaching (this is `stop_instance_before_detaching` working), the old instance is destroyed, a new one boots and runs cloud-init fresh. Expect 5 to 15 minutes, per ADR 0001.

- [ ] **Step 4: Verify survival**

```bash
aws ssm send-command \
  --instance-ids "$(terraform output -raw instance_id)" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /srv/data/.replacement-drill","df -h /srv/data"]' \
  --query 'Command.CommandId' --output text
```

Poll as before. Expected: `m2-replacement-drill` (data survived) and `/srv/data` mounted. Confirm `terraform output -raw host_public_ip` is unchanged and `terraform output -raw instance_id` is a new ID. Update `docs/setup/m2-infra-state.local.md` with the new instance ID.

- [ ] **Step 5: Commit the drill marker**

```bash
git add host/cloud-init.yaml
git commit -m "infra(m2): replacement drill exercised; bootstrap change replaces the Host"
```

---

## Task 8: Documentation and milestone close-out

**Files:**
- Modify: `ROADMAP.md`, `CLAUDE.md`
- Create: `docs/setup/m2-infra-state.md`

- [ ] **Step 1: Update the M2 section of `ROADMAP.md`**

Replace the deliverable bullet:

```
- EC2 t4g.medium in the public subnet, ARM64 Ubuntu 24.04 AMI.
```

with:

```
- EC2 t4g.medium in the public subnet, ARM64 Ubuntu 26.04 AMI resolved via Canonical's SSM public parameter (never a hardcoded AMI ID).
```

and the backups bullet:

```
  - S3 write to the backups bucket
```

with:

```
  - S3 write to the backups bucket (grant deferred to M10 alongside the bucket itself; see the M2 design spec)
```

- [ ] **Step 2: Update the repository-state paragraph in `CLAUDE.md`**

Replace the paragraph beginning "This repo is in the **design + planning phase**." (and its following sentence about no code existing) with:

```markdown
This repo has left the pure design phase. Live today: `infra/` (three Terraform
roots: `bootstrap/`, `aws/`, `cloudflare/`, all applied; M1 network and M2
Graviton host) and `host/cloud-init.yaml` (the cloud Host bootstrap). Still to
come milestone by milestone per `ROADMAP.md`: the Compose stack under
`platform/` (M3), Python tooling under `tools/` (M5 onward), and the reference
project under `template/` (M8). The design spec, milestone plans, ADRs under
`docs/adr/`, and the `CONTEXT.md` glossary remain the sources of truth.
```

Also update the "no build, lint, or test toolchain" sentence in the same section to note: `terraform test` runs in `infra/aws/` (invariant tests), and `terraform fmt`/`validate` apply to all roots.

- [ ] **Step 3: Create `docs/setup/m2-infra-state.md` (public-safe template)**

```markdown
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
```

- [ ] **Step 4: Fill in the local sibling and verify nothing sensitive is staged**

Update `docs/setup/m2-infra-state.local.md` (created in Task 5) to mirror the template with real values and the completion date.

```bash
git status --short
```

Expected: `m2-infra-state.local.md` does NOT appear (gitignored). Only `ROADMAP.md`, `CLAUDE.md`, and `docs/setup/m2-infra-state.md` are pending.

- [ ] **Step 5: Commit**

```bash
git add ROADMAP.md CLAUDE.md docs/setup/m2-infra-state.md
git commit -m "docs(m2): milestone complete; 26.04 host live, state template recorded"
```

- [ ] **Step 6: Request branch review**

Ask the user to review the `feat/m2-graviton-host` branch. Per the project git convention, do not fast-forward merge until they have reviewed it. After approval:

```bash
git checkout main
git merge --ff-only feat/m2-graviton-host
git branch -d feat/m2-graviton-host
git push
```

---

## Self-Review

**Spec coverage** (every M2 design spec section maps to a task):

- §1 scope and hands-on artefacts → Tasks 5, 6.
- §2 decisions → encoded across Tasks 1 (26.04 SSM parameter), 2 (IAM deferral), 3 (self-contained cloud-init), 4 (root placement, data volume, lifecycle, standard credits).
- §3 Terraform shape → Tasks 1 to 4 create exactly the listed files.
- §4 AMI resolution + live check → Task 1 Steps 1 and 2; `ignore_changes = [ami]` in Task 4 Step 3.
- §5 IAM least privilege → Task 2 (no S3 statement; deferral noted in ROADMAP by Task 8).
- §6 instance and volumes → Task 4 (IMDSv2, standard credits, encrypted gp3, `stop_instance_before_detaching`, EIP).
- §7 cloud-init → Task 3 (runcmd wait-format-mount script, platform user, agents).
- §8 testing → Task 4 (tftest), Task 5 (posture), Task 6 (artefacts), Task 7 (replacement drill).
- §9 cost → Global Constraints + Task 5 gating + Task 8 state doc note.
- §10 documentation updates → Task 8.
- §11 out of scope → nothing in this plan builds M3+ material.

**Placeholder scan:** no TBD/TODO; every code step carries full content. The `.md` template's `<instance-id>`-style tokens are intentional placeholders in a public-safe template (Invariant 7), and `<command-id>` in polling commands refers to the ID printed by the immediately preceding command.

**Type/name consistency:** `data.aws_ssm_parameter.ubuntu_arm64` (Tasks 1, 4), `aws_iam_instance_profile.host` name `wkx-host` (Tasks 2, 4), template variable `data_volume_device` (Tasks 3, 4), resources `aws_instance.host` / `aws_ebs_volume.data` / `aws_volume_attachment.data` / `aws_eip.host` / `aws_eip_association.host` (Task 4 and the test in Step 1), outputs `instance_id` / `host_public_ip` / `data_volume_id` / `instance_profile_name` (Tasks 4 to 7 verification commands).

**Known risks flagged inline:** SG-count assertion deliberately omitted from the tftest (set length of two computed IDs can be unknown at plan time); the live SG check happens in Task 5 Step 3 instead. First boot is slow (apt upgrade); Task 5 Step 4 uses `cloud-init status --wait`.
