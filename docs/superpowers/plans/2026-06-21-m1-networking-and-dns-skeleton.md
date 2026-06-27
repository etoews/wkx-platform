# M1: Networking + DNS Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Terraform foundation for the platform — a self-hosted S3 state backend, a public-subnet VPC with IPv6, Cloudflare-only security groups, and a real Cloudflare zone for `wingkongexchange.dev` — so that `dig wingkongexchange.dev NS` returns Cloudflare nameservers and `terraform plan` runs clean from a fresh checkout.

**Architecture:** Three independent Terraform root modules under `infra/`, each with its own state file keyed in one shared S3 bucket. `infra/bootstrap/` creates that bucket on local state then migrates its own state into it (resolving the chicken-and-egg). `infra/aws/` builds the VPC, IPv6, security groups, and two AWS managed prefix lists populated from Cloudflare's published IP list (fetched via the `http` data source, so this root needs no Cloudflare credential). `infra/cloudflare/` imports the registrar-created zone and mints the zone-scoped DNS token Caddy will use in M3. State locking is S3-native (`use_lockfile`), so there is no DynamoDB table.

**Tech Stack:** Terraform 1.15.1 · AWS provider (`hashicorp/aws`) · HTTP provider (`hashicorp/http`) · Cloudflare provider (`cloudflare/cloudflare` v5) · S3 backend with native locking · AWS IAM Identity Center SSO · Cloudflare Registrar.

## Global Constraints

Every task implicitly inherits these. Values are copied verbatim from the design spec, `CLAUDE.md`, and the M1 brainstorm decisions.

- **Region:** `ap-southeast-2` (Sydney). Single region. No second region.
- **Terraform version floor:** `>= 1.10` (required for S3-native `use_lockfile`). Pin `required_version = ">= 1.10"` in every root. Local machine runs 1.15.1.
- **State locking:** S3-native (`use_lockfile = true`). **No DynamoDB lock table** (deliberate deviation from the original ROADMAP wording; ROADMAP is updated in Task 8).
- **No port 22.** No SSH ingress on any security group, ever. Access is via SSM Session Manager (M2). No key pair, no bastion.
- **`web` security group ingress is Cloudflare-only.** Ports 80/443 sourced from the two managed prefix lists only. Never `0.0.0.0/0` / `::/0` on ingress.
- **ARM64 is the platform default** (not relevant to M1 resources, but no resource here forecloses it).
- **Standard tag set via `default_tags`:** `Project = wkx`, `ManagedBy = terraform`, `Repo = wkx-platform`. `Env` and `Service` are **omitted** for every M1 resource — all of them are account/host-level, not per-env or per-service.
- **No real account state in committed files.** Real AWS account ID, Cloudflare account ID, Cloudflare zone ID, and any API token live only in `docs/setup/*.local.md` (gitignored) and in gitignored `*.local.hcl` / `*.local.tfvars` Terraform inputs. Committed `.example` siblings carry placeholders. (Invariant 7.)
- **Per-project Terraform modules require an `env` input with no default.** M1 builds no per-project module (first one, `ecr-repo`, is M6); this rule is *documented* here and enforced from M6 on.
- **Naming — public hostname is env-conditional** (M1 brainstorm decision): prod → `<service>.wingkongexchange.dev` (env hidden); non-prod → `<service>-<env>.wingkongexchange.dev`. All *internal* namespaces stay fully `<service>-<env>` (Compose project, Caddy snippet path, SSM path, log group, data dir).
- **Writing conventions:** New Zealand English in prose. No em dashes. Diagrams in mermaid, never ASCII.
- **Credentials come from the environment, never from code:** AWS via `AWS_PROFILE=wkx-platform` (SSO); Cloudflare via the `CLOUDFLARE_API_TOKEN` env var.

**Real input values** (from `docs/setup/m0-account-state.local.md`; never commit these literals):

- Platform AWS account ID: `<PLATFORM_ACCOUNT_ID>`
- Cloudflare account ID: `<CLOUDFLARE_ACCOUNT_ID>`
- Cloudflare zone ID for `wingkongexchange.dev`: established in Task 0.

---

## File Structure

```
infra/
├── README.md                         run order, bootstrap sequence, fresh-checkout setup
├── .gitignore                         (or root .gitignore additions) — TF state, .local.* inputs
├── bootstrap/
│   ├── versions.tf                    required_version, aws provider, (local→s3 backend)
│   ├── main.tf                        S3 state bucket: versioning, SSE, public-access-block, TLS policy
│   ├── variables.tf                   region, account_id
│   ├── outputs.tf                     state_bucket_name
│   ├── backend.hcl.example            committed placeholder for -backend-config
│   └── terraform.tfvars.example       committed placeholder (account_id)
├── aws/
│   ├── versions.tf                    required_version, aws + http providers
│   ├── backend.tf                     partial S3 backend (bucket via -backend-config)
│   ├── providers.tf                   aws provider default_tags
│   ├── vpc.tf                         vpc, igw, public subnet, IPv6, routes
│   ├── prefix_lists.tf                http data sources + 2 managed prefix lists
│   ├── security_groups.tf             web (ingress 80/443 ex-prefix-lists) + host-egress
│   ├── variables.tf                   region
│   ├── outputs.tf                     vpc/subnet/sg/prefix-list ids
│   ├── backend.hcl.example
│   └── tests/
│       └── security_invariants.tftest.hcl
└── cloudflare/
    ├── versions.tf                    required_version, cloudflare provider v5
    ├── backend.tf                     partial S3 backend
    ├── providers.tf                   cloudflare provider (token from env)
    ├── zone.tf                        cloudflare_zone.apps (imported, prevent_destroy)
    ├── token.tf                       cloudflare_api_token.dns_edit (zone-scoped)
    ├── variables.tf                   cloudflare_account_id, apps_apex
    ├── outputs.tf                     zone_id, name_servers, dns_api_token (sensitive)
    ├── backend.hcl.example
    └── terraform.tfvars.example       committed placeholder (cloudflare_account_id, apps_apex)

docs/setup/m1-infra-state.md           public-safe template recording M1 outputs
docs/setup/m1-infra-state.local.md     gitignored real values (zone id, token, nameservers)
```

**Data-source note (refinement of the approved "managed prefix lists" decision):** Cloudflare's IP ranges are pulled via the `http` data source against `https://www.cloudflare.com/ips-v4` and `https://www.cloudflare.com/ips-v6`, **not** the `cloudflare_ip_ranges` provider data source. This keeps `infra/aws/` free of the Cloudflare provider and any Cloudflare credential, preserving the zero-coupling between the `aws` and `cloudflare` roots. The prefix-list approach itself is unchanged.

---

## Task 0: Manual prerequisites — register the domain and bootstrap Cloudflare auth

**Files:** `docs/setup/m0-account-state.local.md` (append), no committed code.

**Why:** Like the M0 account-creation steps, these require a human in the browser. Terraform's responsibility starts at the zone, not the registration. Everything downstream needs the domain registered, the zone's ID, and an initial Cloudflare token to authenticate the provider.

- [ ] **Step 1: Register `wingkongexchange.dev` via Cloudflare Registrar**

In the Cloudflare dashboard → **Domain Registration → Register Domains** → search `wingkongexchange.dev` → register (~USD $12/yr). Registering through Cloudflare auto-creates an **active zone** with Cloudflare nameservers assigned, so there is no nameserver-repointing step.

If `.dev` is unavailable through Cloudflare Registrar at registration time, the fallback is: register `wingkongexchange.dev` at Porkbun or Namecheap (~USD $12), then in Cloudflare add a zone for `wingkongexchange.dev`, then set the registrar's nameservers to the two Cloudflare nameservers shown. The rest of this plan is identical either way.

- [ ] **Step 2: Record the zone ID**

Cloudflare dashboard → select the `wingkongexchange.dev` zone → **Overview** → right sidebar shows **Zone ID** (32-char hex). Copy it.

- [ ] **Step 3: Create an initial Cloudflare API token for Terraform**

Cloudflare dashboard → **My Profile → API Tokens → Create Token → Create Custom Token**:
- Token name: `wkx-terraform-bootstrap`
- Permissions: `Account` → `API Tokens` → `Edit`; `Zone` → `Zone` → `Edit`; `Zone` → `DNS` → `Edit`.
- Account Resources: Include → your account.
- Zone Resources: Include → Specific zone → `wingkongexchange.dev`.
- Create, then copy the token value (shown once).

This broader token is only ever used locally to run the `cloudflare` root. Terraform will mint a *narrower* zone-scoped DNS token (Task 6) for Caddy's runtime use.

- [ ] **Step 4: Record values in `m0-account-state.local.md`**

Append (this file is gitignored):

```markdown
## M1 — Cloudflare (added during M1)

- Apex domain registered: wingkongexchange.dev (Cloudflare Registrar)
- Zone ID: <32-char-hex>
- Terraform bootstrap token (wkx-terraform-bootstrap): <token-value>   # local use only
```

- [ ] **Step 5: Verify the zone is active and export the token**

```bash
export CLOUDFLARE_API_TOKEN="<token-value-from-step-3>"
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=wingkongexchange.dev" | \
  python3 -c "import sys,json; z=json.load(sys.stdin)['result'][0]; print('id:', z['id']); print('status:', z['status']); print('name_servers:', z['name_servers'])"
```

Expected: prints the zone `id` (matching Step 2), `status: active` (or `pending` if you used the third-party-registrar fallback and nameservers have not propagated yet), and two `*.ns.cloudflare.com` nameservers.

No commit — all changes are in the gitignored `.local.md`.

---

## Task 1: Terraform repo scaffolding

**Files:**
- Create: `infra/README.md`, `infra/.gitignore`
- Modify: none

**Interfaces:**
- Produces: the `infra/` directory and the gitignore rules every later task relies on to keep state and real account values out of git.

- [ ] **Step 1: Create `infra/.gitignore`**

```gitignore
# Terraform working files
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Local-only inputs that carry real account state (Invariant 7)
*.local.hcl
*.local.tfvars

# Keep committed: *.example templates and .terraform.lock.hcl
!*.example
```

- [ ] **Step 2: Confirm `.terraform.lock.hcl` is NOT ignored**

Run:

```bash
git check-ignore -v infra/aws/.terraform.lock.hcl; echo "exit: $?"
```

Expected: exit `1` and no output (the lock file is not ignored, so it will be committed for reproducible provider versions). The root `.gitignore` already ignores `.env`/`.envrc`; confirm it does not ignore `*.tfstate` globally in a conflicting way (it does not).

- [ ] **Step 3: Create `infra/README.md`**

```markdown
# infra — Terraform (Layer 1)

Three independent root modules, each with its own state file in one shared S3 bucket:

| Root           | State key                      | Provider creds            |
|----------------|--------------------------------|---------------------------|
| `bootstrap/`   | `bootstrap/terraform.tfstate`  | AWS (SSO)                 |
| `aws/`         | `aws/terraform.tfstate`        | AWS (SSO)                 |
| `cloudflare/`  | `cloudflare/terraform.tfstate` | `CLOUDFLARE_API_TOKEN`    |

## One-time bootstrap (first run only)

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.local.tfvars   # fill in account_id from m0-account-state.local.md
terraform init
terraform apply -var-file=terraform.local.tfvars
# then migrate this root's own state into the bucket it just created:
cp backend.hcl.example backend.local.hcl             # fill in the bucket name from the apply output
terraform init -migrate-state -backend-config=backend.local.hcl
```

## Fresh-checkout setup (any machine, after bootstrap exists)

For each of `aws/` and `cloudflare/`:

```bash
aws sso login                       # AWS_PROFILE=wkx-platform
export CLOUDFLARE_API_TOKEN=...      # for the cloudflare root only
cp backend.hcl.example backend.local.hcl       # fill bucket name
cp terraform.tfvars.example terraform.local.tfvars  # where present; fill from m0-account-state.local.md
terraform init -backend-config=backend.local.hcl
terraform plan -var-file=terraform.local.tfvars
```

State locking is S3-native (`use_lockfile = true`); there is no DynamoDB table.
```

- [ ] **Step 4: Commit**

```bash
git add infra/.gitignore infra/README.md
git commit -m "infra(m1): scaffold infra/ root layout and gitignore"
```

---

## Task 2: Bootstrap the state backend bucket

**Files:**
- Create: `infra/bootstrap/versions.tf`, `infra/bootstrap/main.tf`, `infra/bootstrap/variables.tf`, `infra/bootstrap/outputs.tf`, `infra/bootstrap/terraform.tfvars.example`, `infra/bootstrap/backend.hcl.example`

**Interfaces:**
- Produces: an S3 bucket named `wkx-tfstate-<account_id>` (versioned, AES256-encrypted, public-access-blocked, TLS-only) that the `aws` and `cloudflare` roots use as their backend. Output `state_bucket_name`.

- [ ] **Step 1: Write `infra/bootstrap/variables.tf`**

```hcl
variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "ap-southeast-2"
}

variable "account_id" {
  description = "Platform AWS account ID. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
```

- [ ] **Step 2: Write `infra/bootstrap/versions.tf`**

Start with **local state** (no backend block). The S3 backend block is added in Step 8 and migrated.

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wkx"
      ManagedBy = "terraform"
      Repo      = "wkx-platform"
    }
  }
}
```

- [ ] **Step 3: Write `infra/bootstrap/main.tf`**

```hcl
locals {
  state_bucket_name = "wkx-tfstate-${var.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true
}

resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.state.arn,
        "${aws_s3_bucket.state.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
```

- [ ] **Step 4: Write `infra/bootstrap/outputs.tf`**

```hcl
output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Use as -backend-config bucket value."
  value       = aws_s3_bucket.state.bucket
}
```

- [ ] **Step 5: Write the committed `.example` templates**

`infra/bootstrap/terraform.tfvars.example`:

```hcl
# Copy to terraform.local.tfvars (gitignored) and fill from m0-account-state.local.md
account_id = "REPLACE_WITH_12_DIGIT_PLATFORM_ACCOUNT_ID"
```

`infra/bootstrap/backend.hcl.example`:

```hcl
# Copy to backend.local.hcl (gitignored) after the first apply prints state_bucket_name
bucket = "wkx-tfstate-REPLACE_WITH_ACCOUNT_ID"
```

- [ ] **Step 6: Format, validate**

```bash
cd infra/bootstrap
terraform fmt
cp terraform.tfvars.example terraform.local.tfvars   # then edit: set the real account_id (<PLATFORM_ACCOUNT_ID>)
terraform init
terraform validate
```

Expected: `fmt` leaves files unchanged after one pass; `init` succeeds (local backend); `validate` prints "Success! The configuration is valid."

- [ ] **Step 7: Apply with local state**

```bash
terraform apply -var-file=terraform.local.tfvars
```

Expected: creates 5 resources (`aws_s3_bucket.state` and its four config resources). Output `state_bucket_name = "wkx-tfstate-<PLATFORM_ACCOUNT_ID>"`. Verify:

```bash
aws s3api get-bucket-versioning --bucket "wkx-tfstate-<PLATFORM_ACCOUNT_ID>"
```

Expected: `{"Status": "Enabled"}`.

- [ ] **Step 8: Add the S3 backend block and migrate state into the bucket**

Append to `infra/bootstrap/versions.tf` inside the `terraform { }` block:

```hcl
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket supplied via -backend-config (see backend.hcl.example)
  }
```

Then migrate:

```bash
cp backend.hcl.example backend.local.hcl    # edit: bucket = "wkx-tfstate-<PLATFORM_ACCOUNT_ID>"
terraform init -migrate-state -backend-config=backend.local.hcl
```

Expected: prompt "Do you want to copy existing state to the new backend?" → `yes`. Init reports state successfully migrated. Confirm the object exists:

```bash
aws s3 ls "s3://wkx-tfstate-<PLATFORM_ACCOUNT_ID>/bootstrap/"
```

Expected: lists `terraform.tfstate`.

- [ ] **Step 9: Remove the now-stale local state and re-validate**

```bash
rm -f terraform.tfstate terraform.tfstate.backup
terraform plan -var-file=terraform.local.tfvars
```

Expected: "No changes. Your infrastructure matches the configuration." (state now read from S3).

- [ ] **Step 10: Commit**

```bash
git add infra/bootstrap/versions.tf infra/bootstrap/main.tf infra/bootstrap/variables.tf \
        infra/bootstrap/outputs.tf infra/bootstrap/terraform.tfvars.example \
        infra/bootstrap/backend.hcl.example infra/bootstrap/.terraform.lock.hcl
git commit -m "infra(m1): self-hosting S3 state backend with native locking"
```

(`backend.local.hcl` and `terraform.local.tfvars` are gitignored and must not appear in the staged set — verify with `git status` before committing.)

---

## Task 3: AWS VPC, public subnet, IPv6

**Files:**
- Create: `infra/aws/versions.tf`, `infra/aws/backend.tf`, `infra/aws/providers.tf`, `infra/aws/variables.tf`, `infra/aws/vpc.tf`, `infra/aws/outputs.tf`, `infra/aws/backend.hcl.example`

**Interfaces:**
- Consumes: the state bucket from Task 2 (via `-backend-config`).
- Produces: `aws_vpc.main`, `aws_subnet.public`, `aws_internet_gateway.main`; outputs `vpc_id`, `public_subnet_id`. Later tasks in this root attach security groups and prefix lists to `aws_vpc.main`.

- [ ] **Step 1: Write `infra/aws/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
```

- [ ] **Step 2: Write `infra/aws/backend.tf`**

```hcl
terraform {
  backend "s3" {
    key          = "aws/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket supplied via -backend-config (see backend.hcl.example)
  }
}
```

- [ ] **Step 3: Write `infra/aws/variables.tf`**

```hcl
variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-2"
}
```

- [ ] **Step 4: Write `infra/aws/providers.tf`**

```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wkx"
      ManagedBy = "terraform"
      Repo      = "wkx-platform"
    }
  }
}
```

- [ ] **Step 5: Write `infra/aws/vpc.tf`**

```hcl
resource "aws_vpc" "main" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = true
  enable_dns_hostnames             = true

  tags = { Name = "wkx" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wkx" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "${var.region}a"

  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, 0)
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = { Name = "wkx-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "wkx-public" }
}

resource "aws_route" "ipv4_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route" "ipv6_default" {
  route_table_id              = aws_route_table.public.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

- [ ] **Step 6: Write `infra/aws/outputs.tf`** (extended in later tasks)

```hcl
output "vpc_id" {
  description = "Platform VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID (the M2 host lands here)."
  value       = aws_subnet.public.id
}
```

- [ ] **Step 7: Write `infra/aws/backend.hcl.example`**

```hcl
# Copy to backend.local.hcl (gitignored); fill from m0-account-state.local.md
bucket = "wkx-tfstate-REPLACE_WITH_ACCOUNT_ID"
```

- [ ] **Step 8: Init, format, validate, plan**

```bash
cd infra/aws
terraform fmt
cp backend.hcl.example backend.local.hcl    # edit: bucket = "wkx-tfstate-<PLATFORM_ACCOUNT_ID>"
terraform init -backend-config=backend.local.hcl
terraform validate
terraform plan
```

Expected: `validate` succeeds; `plan` shows the VPC, IGW, subnet, route table, two routes, and the association to add — no errors.

- [ ] **Step 9: Apply and verify with the AWS CLI**

```bash
terraform apply
aws ec2 describe-vpcs --vpc-ids "$(terraform output -raw vpc_id)" \
  --query 'Vpcs[0].{Cidr:CidrBlock,Ipv6:Ipv6CidrBlockAssociationSet[0].Ipv6CidrBlock}'
```

Expected: prints the `10.0.0.0/16` CIDR and a non-null IPv6 block (e.g. `2406:da1c:...::/56`).

- [ ] **Step 10: Commit**

```bash
git add infra/aws/versions.tf infra/aws/backend.tf infra/aws/providers.tf \
        infra/aws/variables.tf infra/aws/vpc.tf infra/aws/outputs.tf \
        infra/aws/backend.hcl.example infra/aws/.terraform.lock.hcl
git commit -m "infra(m1): VPC with public subnet, IGW, dual-stack IPv6 routing"
```

---

## Task 4: Cloudflare IP managed prefix lists

**Files:**
- Create: `infra/aws/prefix_lists.tf`
- Modify: `infra/aws/outputs.tf`

**Interfaces:**
- Consumes: the public Cloudflare IP lists via the `http` data source.
- Produces: `aws_ec2_managed_prefix_list.cloudflare_ipv4` and `...cloudflare_ipv6`; outputs `cloudflare_ipv4_prefix_list_id`, `cloudflare_ipv6_prefix_list_id`. Task 5's `web` security group references both.

- [ ] **Step 1: Write `infra/aws/prefix_lists.tf`**

```hcl
# Cloudflare's published origin IP ranges (https://www.cloudflare.com/ips/).
# Pulled via the http data source so this root needs no Cloudflare provider/credential.
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ipv6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  cloudflare_ipv4_cidrs = [
    for c in split("\n", trimspace(data.http.cloudflare_ipv4.response_body)) : c if c != ""
  ]
  cloudflare_ipv6_cidrs = [
    for c in split("\n", trimspace(data.http.cloudflare_ipv6.response_body)) : c if c != ""
  ]
}

resource "aws_ec2_managed_prefix_list" "cloudflare_ipv4" {
  name           = "wkx-cloudflare-ipv4"
  address_family = "IPv4"
  max_entries    = 30 # Cloudflare publishes ~15; headroom avoids churn-driven replacement.

  dynamic "entry" {
    for_each = toset(local.cloudflare_ipv4_cidrs)
    content {
      cidr = entry.value
    }
  }

  tags = { Name = "wkx-cloudflare-ipv4" }
}

resource "aws_ec2_managed_prefix_list" "cloudflare_ipv6" {
  name           = "wkx-cloudflare-ipv6"
  address_family = "IPv6"
  max_entries    = 20 # Cloudflare publishes ~7; headroom.

  dynamic "entry" {
    for_each = toset(local.cloudflare_ipv6_cidrs)
    content {
      cidr = entry.value
    }
  }

  tags = { Name = "wkx-cloudflare-ipv6" }
}
```

- [ ] **Step 2: Append outputs to `infra/aws/outputs.tf`**

```hcl
output "cloudflare_ipv4_prefix_list_id" {
  description = "Managed prefix list of Cloudflare IPv4 ranges."
  value       = aws_ec2_managed_prefix_list.cloudflare_ipv4.id
}

output "cloudflare_ipv6_prefix_list_id" {
  description = "Managed prefix list of Cloudflare IPv6 ranges."
  value       = aws_ec2_managed_prefix_list.cloudflare_ipv6.id
}
```

- [ ] **Step 3: Validate and plan**

```bash
cd infra/aws
terraform fmt
terraform validate
terraform plan
```

Expected: plan shows both prefix lists with ~15 IPv4 and ~7 IPv6 entries each. If `max_entries` is below the live count, raise it and re-plan.

- [ ] **Step 4: Apply and verify entry counts**

```bash
terraform apply
aws ec2 get-managed-prefix-list-entries \
  --prefix-list-id "$(terraform output -raw cloudflare_ipv4_prefix_list_id)" \
  --query 'length(Entries)'
```

Expected: a positive integer matching the line count of `https://www.cloudflare.com/ips-v4` (around 15).

- [ ] **Step 5: Commit**

```bash
git add infra/aws/prefix_lists.tf infra/aws/outputs.tf
git commit -m "infra(m1): Cloudflare IP managed prefix lists from published ranges"
```

---

## Task 5: Security groups (test-first)

**Files:**
- Create: `infra/aws/tests/security_invariants.tftest.hcl`, `infra/aws/security_groups.tf`
- Modify: `infra/aws/outputs.tf`

**Interfaces:**
- Consumes: `aws_vpc.main` (Task 3), both prefix lists (Task 4).
- Produces: `aws_security_group.web` (ingress 80/443 from Cloudflare prefix lists only), `aws_security_group.host_egress` (all egress); outputs `web_sg_id`, `host_egress_sg_id`. The M2 host attaches both.

- [ ] **Step 1: Write the failing invariant test `infra/aws/tests/security_invariants.tftest.hcl`**

```hcl
# Encodes the non-negotiable SG invariants (CLAUDE.md §invariants 2 and 3) as a plan-time check.
run "web_sg_is_cloudflare_only_and_no_ssh" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.web_https_ipv4.prefix_list_id != null
    error_message = "web HTTPS ingress must source from the Cloudflare prefix list, not a CIDR."
  }

  assert {
    condition = alltrue([
      aws_vpc_security_group_ingress_rule.web_http_ipv4.prefix_list_id != null,
      aws_vpc_security_group_ingress_rule.web_http_ipv6.prefix_list_id != null,
      aws_vpc_security_group_ingress_rule.web_https_ipv4.prefix_list_id != null,
      aws_vpc_security_group_ingress_rule.web_https_ipv6.prefix_list_id != null,
    ])
    error_message = "Every web ingress rule must reference a prefix list (Cloudflare-only)."
  }

  assert {
    condition = alltrue([
      for p in [
        aws_vpc_security_group_ingress_rule.web_http_ipv4.from_port,
        aws_vpc_security_group_ingress_rule.web_http_ipv6.from_port,
        aws_vpc_security_group_ingress_rule.web_https_ipv4.from_port,
        aws_vpc_security_group_ingress_rule.web_https_ipv6.from_port,
      ] : p == 80 || p == 443
    ])
    error_message = "web ingress ports must be exactly 80 or 443. No SSH (22), ever."
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd infra/aws
terraform test
```

Expected: FAIL — the `aws_vpc_security_group_ingress_rule.web_*` resources do not exist yet ("Reference to undeclared resource").

- [ ] **Step 3: Write `infra/aws/security_groups.tf`**

```hcl
# web: ingress only. 80/443 from Cloudflare prefix lists. No port 22. No egress here
# (egress is owned by host_egress; multiple SGs on one ENI union their allows).
resource "aws_security_group" "web" {
  name        = "wkx-web"
  description = "Ingress 80/443 from Cloudflare ranges only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wkx-web" }
}

resource "aws_vpc_security_group_ingress_rule" "web_http_ipv4" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from Cloudflare IPv4"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "web_https_ipv4" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from Cloudflare IPv4"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "web_http_ipv6" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP from Cloudflare IPv6"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv6.id
}

resource "aws_vpc_security_group_ingress_rule" "web_https_ipv6" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from Cloudflare IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv6.id
}

# host_egress: all outbound, both families. No ingress.
resource "aws_security_group" "host_egress" {
  name        = "wkx-host-egress"
  description = "All outbound traffic"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wkx-host-egress" }
}

resource "aws_vpc_security_group_egress_rule" "host_egress_ipv4" {
  security_group_id = aws_security_group.host_egress.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "host_egress_ipv6" {
  security_group_id = aws_security_group.host_egress.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
terraform fmt
terraform test
```

Expected: PASS — `1 passed, 0 failed`.

- [ ] **Step 5: Append outputs to `infra/aws/outputs.tf`**

```hcl
output "web_sg_id" {
  description = "Security group allowing 80/443 from Cloudflare ranges only."
  value       = aws_security_group.web.id
}

output "host_egress_sg_id" {
  description = "Security group allowing all outbound."
  value       = aws_security_group.host_egress.id
}
```

- [ ] **Step 6: Apply and verify no port 22 exists**

```bash
terraform apply
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(terraform output -raw web_sg_id)" \
  --query 'SecurityGroupRules[?FromPort==`22`]'
```

Expected: `[]` (empty — no SSH rule). Confirm the four ingress rules reference prefix lists:

```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(terraform output -raw web_sg_id)" \
  --query 'SecurityGroupRules[?!IsEgress].{Port:FromPort,PrefixList:PrefixListId}'
```

Expected: four entries, ports 80/80/443/443, each with a non-null `PrefixList`.

- [ ] **Step 7: Commit**

```bash
git add infra/aws/security_groups.tf infra/aws/tests/security_invariants.tftest.hcl infra/aws/outputs.tf
git commit -m "infra(m1): web (Cloudflare-only) and host-egress security groups + invariant test"
```

---

## Task 6: Cloudflare zone import and zone-scoped DNS token

**Files:**
- Create: `infra/cloudflare/versions.tf`, `infra/cloudflare/backend.tf`, `infra/cloudflare/providers.tf`, `infra/cloudflare/variables.tf`, `infra/cloudflare/zone.tf`, `infra/cloudflare/token.tf`, `infra/cloudflare/outputs.tf`, `infra/cloudflare/backend.hcl.example`, `infra/cloudflare/terraform.tfvars.example`

**Interfaces:**
- Consumes: the registrar-created zone (Task 0), `CLOUDFLARE_API_TOKEN` env var, `cloudflare_account_id` var.
- Produces: `cloudflare_zone.apps` (imported), `cloudflare_api_token.dns_edit`; outputs `zone_id`, `name_servers`, `dns_api_token` (sensitive). M3 consumes the DNS token for Caddy DNS-01.

> **Provider note:** Cloudflare provider v5 was a large rewrite from v4. Before writing resource bodies, open the v5 docs for `cloudflare_zone` and `cloudflare_api_token` and confirm argument names. The bodies below reflect the v5 schema (zone uses an `account = { id = ... }` block and `name`; token uses `policies` blocks). If an argument name differs in the installed v5 minor version, `terraform validate` will name it; adjust and re-run. Do not silently fall back to v4 syntax.

- [ ] **Step 1: Write `infra/cloudflare/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
```

- [ ] **Step 2: Write `infra/cloudflare/backend.tf`**

```hcl
terraform {
  backend "s3" {
    key          = "cloudflare/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket supplied via -backend-config (see backend.hcl.example)
  }
}
```

The S3 backend uses AWS credentials (SSO), independent of the Cloudflare provider creds.

- [ ] **Step 3: Write `infra/cloudflare/variables.tf`**

```hcl
variable "cloudflare_account_id" {
  description = "Cloudflare account ID. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string
}

variable "apps_apex" {
  description = "Apex domain for Mode-3 apps."
  type        = string
  default     = "wingkongexchange.dev"
}
```

- [ ] **Step 4: Write `infra/cloudflare/providers.tf`**

```hcl
# Reads the token from the CLOUDFLARE_API_TOKEN environment variable.
provider "cloudflare" {}
```

- [ ] **Step 5: Write `infra/cloudflare/zone.tf`**

```hcl
resource "cloudflare_zone" "apps" {
  account = {
    id = var.cloudflare_account_id
  }
  name = var.apps_apex
  type = "full"

  lifecycle {
    prevent_destroy = true # never let `destroy` remove the registered zone
  }
}
```

- [ ] **Step 6: Write `infra/cloudflare/token.tf`**

```hcl
# Narrow zone-scoped token for Caddy's DNS-01 challenge (M3). Stored in state
# (encrypted bucket); moved to SSM in M5.
resource "cloudflare_api_token" "dns_edit" {
  name = "wkx-caddy-dns01"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_api_token_permission_groups_list.all.result[
        index(data.cloudflare_api_token_permission_groups_list.all.result[*].name, "DNS Write")
      ].id
    }]
    resources = {
      "com.cloudflare.api.account.zone.${cloudflare_zone.apps.id}" = "*"
    }
  }]
}

data "cloudflare_api_token_permission_groups_list" "all" {}
```

> If the permission-groups data source or the `DNS Write` group name differs in the installed v5 minor version, list them with the verification command in Step 8 and adjust the lookup. The goal is a token scoped to **DNS:Edit on the `wingkongexchange.dev` zone only**.

- [ ] **Step 7: Write `infra/cloudflare/outputs.tf`**

```hcl
output "zone_id" {
  description = "Cloudflare zone ID for the apps apex."
  value       = cloudflare_zone.apps.id
}

output "name_servers" {
  description = "Cloudflare nameservers assigned to the zone."
  value       = cloudflare_zone.apps.name_servers
}

output "dns_api_token" {
  description = "Zone-scoped DNS:Edit token for Caddy DNS-01 (M3)."
  value       = cloudflare_api_token.dns_edit.value
  sensitive   = true
}
```

- [ ] **Step 8: Write the `.example` templates**

`infra/cloudflare/backend.hcl.example`:

```hcl
bucket = "wkx-tfstate-REPLACE_WITH_ACCOUNT_ID"
```

`infra/cloudflare/terraform.tfvars.example`:

```hcl
# Copy to terraform.local.tfvars (gitignored); fill from m0-account-state.local.md
cloudflare_account_id = "REPLACE_WITH_CLOUDFLARE_ACCOUNT_ID"
apps_apex             = "wingkongexchange.dev"
```

- [ ] **Step 9: Init, then import the existing zone**

```bash
cd infra/cloudflare
export CLOUDFLARE_API_TOKEN="<wkx-terraform-bootstrap token from m0-account-state.local.md>"
terraform fmt
cp backend.hcl.example backend.local.hcl            # edit bucket
cp terraform.tfvars.example terraform.local.tfvars  # edit cloudflare_account_id
terraform init -backend-config=backend.local.hcl
terraform validate
terraform import -var-file=terraform.local.tfvars cloudflare_zone.apps "<zone-id-from-task-0>"
```

Expected: `validate` succeeds; `import` reports "Import successful!" for `cloudflare_zone.apps`.

- [ ] **Step 10: Plan and apply**

```bash
terraform plan -var-file=terraform.local.tfvars
```

Expected: zone shows no changes (or only benign drift on settings); `cloudflare_api_token.dns_edit` is the one resource to **add**. Then:

```bash
terraform apply -var-file=terraform.local.tfvars
terraform output -raw zone_id
terraform output name_servers
```

Expected: `zone_id` matches Task 0; `name_servers` lists two `*.ns.cloudflare.com`.

- [ ] **Step 11: Record outputs and verify the new token works**

```bash
DNS_TOKEN="$(terraform output -raw dns_api_token)"
curl -s -H "Authorization: Bearer $DNS_TOKEN" \
  "https://api.cloudflare.com/client/v4/user/tokens/verify" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['status'])"
```

Expected: `active`.

Then create `docs/setup/m1-infra-state.local.md` (gitignored) recording: `zone_id`, `name_servers`, and `dns_api_token` (the Caddy token). Do **not** print the token into any committed file.

- [ ] **Step 12: Commit**

```bash
git add infra/cloudflare/versions.tf infra/cloudflare/backend.tf infra/cloudflare/providers.tf \
        infra/cloudflare/variables.tf infra/cloudflare/zone.tf infra/cloudflare/token.tf \
        infra/cloudflare/outputs.tf infra/cloudflare/backend.hcl.example \
        infra/cloudflare/terraform.tfvars.example infra/cloudflare/.terraform.lock.hcl
git commit -m "infra(m1): import wingkongexchange.dev Cloudflare zone and mint zone-scoped DNS token"
```

(Verify `git status` shows no `*.local.*` files staged.)

---

## Task 7: Hands-on artifact — DNS resolves and plan is clean

**Files:** none (verification only).

**Why:** This is the M1 deliverable from `ROADMAP.md`: `dig wingkongexchange.dev NS` returns Cloudflare nameservers, and `terraform plan` runs clean from a fresh checkout.

- [ ] **Step 1: `dig` the nameservers**

```bash
dig +short wingkongexchange.dev NS
```

Expected: two `*.ns.cloudflare.com` records (matching `name_servers` from Task 6). If you used the third-party-registrar fallback in Task 0 and this is empty, the registrar's nameservers have not propagated yet — set them to the Cloudflare pair and wait (up to a few hours), then re-run.

- [ ] **Step 2: Prove a clean plan from a fresh checkout**

```bash
cd "$(mktemp -d)"
git clone <repo-url> wkx-platform && cd wkx-platform/infra
# recreate the gitignored local inputs from m0-account-state.local.md:
#   bootstrap/{backend.local.hcl,terraform.local.tfvars}
#   aws/backend.local.hcl
#   cloudflare/{backend.local.hcl,terraform.local.tfvars}
aws sso login
export CLOUDFLARE_API_TOKEN="<bootstrap token>"

for root in bootstrap aws cloudflare; do
  echo "=== $root ==="
  ( cd "$root" \
    && terraform init -backend-config=backend.local.hcl \
    && terraform plan -var-file=terraform.local.tfvars -detailed-exitcode )
done
```

Expected: each root's `plan` ends with exit code `0` and "No changes. Your infrastructure matches the configuration." (For `aws`, which has no var-file, drop the `-var-file` flag.)

- [ ] **Step 3: Record the artifact result**

Append the `dig` output and the three clean-plan confirmations to `docs/setup/m1-infra-state.local.md`. No commit (gitignored).

---

## Task 8: Documentation updates

**Files:**
- Modify: `ROADMAP.md`, `docs/superpowers/specs/2026-05-01-wkx-platform-design.md`, `CLAUDE.md`, `README.md`
- Create: `docs/setup/m1-infra-state.md` (public-safe template)

**Why:** `wingkongexchange.dev` is now real, so `<APPS_APEX>` stops being a placeholder; the hostname convention now hides `-env` for prod; and the locking deliverable changed to S3-native.

- [ ] **Step 1: ROADMAP.md — switch the M1 locking deliverable to S3-native**

Replace the M1 deliverable bullet:

```
- Terraform state backend in the platform account: S3 bucket (versioned, encrypted) + DynamoDB lock table.
```

with:

```
- Terraform state backend in the platform account: S3 bucket (versioned, encrypted) with S3-native state locking (`use_lockfile`). No DynamoDB lock table (see the M1 plan for rationale).
```

- [ ] **Step 2: ROADMAP.md — fix hostname examples for the env-conditional convention**

In M3 deliverables and hands-on artifact, replace `hello-prod.<APPS_APEX>` with `hello.wingkongexchange.dev`. In M8's hands-on artifact, replace `https://prod-notes.<APPS_APEX>` with `https://notes.wingkongexchange.dev`. While here, fix the stale env-first SSM path in M5's deliverables/artifact (`/wkx/prod/hello/MESSAGE` → `/wkx/hello/prod/MESSAGE`) to match the service-first convention in spec §6. Leave M11's `<service>-pr-42.<APPS_APEX>` as `<service>-pr-42.wingkongexchange.dev` (non-prod keeps the env).

- [ ] **Step 3: design spec §6 — env-conditional hostname**

In the naming-conventions table, replace the Hostname row value `<service>-<env>.<APPS_APEX>` with: `prod: <service>.wingkongexchange.dev · non-prod: <service>-<env>.wingkongexchange.dev`. Add a sentence beneath the table: "The public hostname hides the env for `prod` (so users see `hello.wingkongexchange.dev`, never `hello-prod.wingkongexchange.dev`); every internal namespace keeps the explicit `<service>-<env>` form. This presentation choice does not weaken the explicit-env rule — deploys still name their env."

- [ ] **Step 4: Replace `<APPS_APEX>` with `wingkongexchange.dev` across prose**

Update remaining `<APPS_APEX>` occurrences in `README.md`, `CLAUDE.md`, and the design spec glossary to `wingkongexchange.dev`, except keep `<APP_DOMAIN>` (Mode-1 per-app domains) as a placeholder. In `CLAUDE.md`, update the line "`<APPS_APEX>` and `<APP_DOMAIN>` are intentional placeholders through M10" to "`<APP_DOMAIN>` is an intentional placeholder through M10. `<APPS_APEX>` is now `wingkongexchange.dev` (registered in M1)." Verify with:

```bash
grep -rn "APPS_APEX" README.md CLAUDE.md ROADMAP.md docs/superpowers/specs/
```

Expected: only deliberate residual references (e.g. inside the M1 plan itself) remain; prose uses `wingkongexchange.dev`.

- [ ] **Step 5: CLAUDE.md naming table — env-conditional hostname**

In the "Naming patterns" table, change the `Hostname (Mode 3)` row pattern from `<service>-<env>.<APPS_APEX>` to `prod: <service>.wingkongexchange.dev · else: <service>-<env>.wingkongexchange.dev`.

- [ ] **Step 6: Create `docs/setup/m1-infra-state.md` (public-safe template)**

```markdown
# M1 Infra State (template)

> Public-safe template. Real values live in the gitignored `m1-infra-state.local.md`.

## Terraform state backend
- State bucket: `wkx-tfstate-<PLATFORM_ACCOUNT_ID>`
- Locking: S3-native (`use_lockfile`), no DynamoDB
- State keys: `bootstrap/`, `aws/`, `cloudflare/`

## Cloudflare
- Apex: `wingkongexchange.dev`
- Zone ID: `<32-char-hex>`
- Nameservers: `<ns1>.ns.cloudflare.com`, `<ns2>.ns.cloudflare.com`
- Caddy DNS-01 token (`wkx-caddy-dns01`): stored in `m1-infra-state.local.md`; moves to SSM in M5

## Outputs (from `terraform output`)
- aws: `vpc_id`, `public_subnet_id`, `web_sg_id`, `host_egress_sg_id`, prefix-list ids
```

- [ ] **Step 7: Commit**

```bash
git add ROADMAP.md docs/superpowers/specs/2026-05-01-wkx-platform-design.md CLAUDE.md README.md docs/setup/m1-infra-state.md
git commit -m "docs(m1): make wingkongexchange.dev concrete, env-conditional hostname, S3-native locking"
```

---

## Task 9: Cost-allocation tags and milestone close-out

**Files:**
- Modify: `docs/setup/m1-infra-state.md` (status banner)

**Why:** The tag set is applied; activating `Project`/`Env`/`Service` for cost allocation is a one-time manual Billing-console step the design calls for, and the milestone needs a recorded close.

- [ ] **Step 1: Activate cost-allocation tags (manual)**

AWS Billing console → **Cost allocation tags** → user-defined tags → activate `Project`, `Env`, `Service`. (They appear once at least one tagged resource exists, which is now true. `Env`/`Service` are activated ahead of the per-service resources that arrive in M6.)

- [ ] **Step 2: Verify the tag set landed on a resource**

```bash
aws ec2 describe-vpcs --vpc-ids "$(cd infra/aws && terraform output -raw vpc_id)" \
  --query 'Vpcs[0].Tags'
```

Expected: includes `Project=wkx`, `ManagedBy=terraform`, `Repo=wkx-platform`, `Name=wkx`.

- [ ] **Step 3: Append M1 status banner to `docs/setup/m1-infra-state.md`**

```markdown
## M1 status
- M1 completed: 2026-06-21 (replace with actual date)
- Hands-on artifact: `dig wingkongexchange.dev NS` returns Cloudflare nameservers; `terraform plan` clean across all three roots.
- Ready for M2: Graviton host.
```

- [ ] **Step 4: Final commit and integrate the branch**

```bash
git add docs/setup/m1-infra-state.md
git commit -m "docs(m1): milestone complete, cost-allocation tags activated"
```

Then follow the project git convention: `git checkout main && git merge --ff-only feat/m1-networking-and-dns-skeleton && git branch -d feat/m1-networking-and-dns-skeleton`, and push.

---

## Self-Review

**Spec coverage** — every M1 ROADMAP deliverable maps to a task:

- S3 state backend (versioned, encrypted) + locking → Task 2 (S3-native locking; ROADMAP updated in Task 8 Step 1).
- VPC, one public subnet, IGW, default route, IPv6 → Task 3.
- `web` SG (80/443 from Cloudflare ranges) + `host-egress` (all out), no port 22 → Tasks 4 (prefix lists) + 5 (SGs + invariant test).
- Cloudflare zone for the apex → Tasks 0 (register/import prep) + 6 (import + manage).
- Per-project modules require `env` (no default) → documented in Global Constraints; no module built in M1 (first is M6).
- AWS tagging strategy via `default_tags` → applied in every provider block (Tasks 2, 3); cost-allocation activation in Task 9.
- Cloudflare zone-scoped API token (deferred from M0) → Task 6 (`cloudflare_api_token.dns_edit`).
- Hands-on artifact (`dig` + clean plan) → Task 7.

**Placeholder scan:** No "TBD"/"TODO" in step bodies. The two provider-version verification notes (Cloudflare v5 schema in Task 6; `max_entries` headroom in Task 4) are explicit verification steps with concrete fallback commands, not deferred work. The `.example` files intentionally contain `REPLACE_WITH_*` tokens — that is their purpose.

**Type/name consistency:** Resource names are consistent across tasks — `aws_vpc.main`, `aws_subnet.public`, `aws_ec2_managed_prefix_list.cloudflare_ipv4|ipv6`, `aws_security_group.web|host_egress`, the four `web_{http,https}_ipv{4,6}` ingress rules (same names in the test in Task 5 Step 1 and the resource file in Step 3), `cloudflare_zone.apps`, `cloudflare_api_token.dns_edit`. Output names referenced by verification commands (`vpc_id`, `web_sg_id`, `cloudflare_ipv4_prefix_list_id`, `zone_id`, `name_servers`, `dns_api_token`) match their `outputs.tf` definitions.

**Invariant coverage:** No port 22 (Task 5 test + Step 6 check). Cloudflare-only ingress via prefix lists (Task 5 test). No ALB/NAT/RDS/second region introduced. Real account state confined to gitignored `*.local.*` (Tasks 1, 2, 6 staging checks). S3-native locking replaces DynamoDB consistently (Global Constraints + Tasks 2/3/6 backends + ROADMAP update).

**Known external dependencies:** Task 0 (domain registration, zone activation) and Task 9 Step 1 (cost-allocation activation) require a human in the browser and, for the third-party-registrar fallback, nameserver propagation that can take hours. These are unavoidable and flagged inline.
