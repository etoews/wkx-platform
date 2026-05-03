# M0: Prerequisites — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **This milestone is mostly manual cloud-console setup with verification commands.** It produces near-zero local code. The "tests" are AWS / Cloudflare / shell verification commands that prove each step landed correctly. Non-interactive execution is impossible for the AWS account-creation steps — those require a human in the browser. An agent can dispatch verifications and document state but the user must click through console signup flows.

**Goal:** Stand up the foundational accounts, identity, and local tooling required for M1 (Terraform-managed VPC + DNS skeleton). At completion: SSO into the AWS platform member account works end-to-end, all required CLI tools are installed, and the local repo is ready for Terraform code.

**Architecture:** Two new AWS accounts inside an Organization (fresh management account + a platform member account); IAM Identity Center handles SSO into the member account; the existing AWS account is untouched. A separate Cloudflare account is created (zone-scoped API token deferred to M1). Local tooling is verified/installed on the macOS host; the rest lives in a devcontainer in M1.

**Tech Stack:** AWS Organizations · AWS IAM Identity Center · AWS CLI v2 · Cloudflare · mise · Terraform · uv · Docker Desktop · GitHub CLI · macOS.

**Source of truth for design context:** `docs/superpowers/specs/2026-05-01-wkx-platform-design.md` and `ROADMAP.md`.

---

## File Structure

This milestone produces almost no code. The only files touched in the repo are:

- **Modify** `~/.aws/config` — adds an SSO session and a profile for the platform account. Local-only, not in the repo.
- **Create** `docs/setup/m0-account-state.md` — captures the immutable IDs created during M0 (AWS account IDs, IdC instance ARN, SSO start URL) so M1 Terraform can reference them. Committed to the repo.

No source code, no Terraform yet — that's M1.

---

## Task 1: Email aliases

**Files:** none.

**Why:** The mgmt account and platform account each need a unique root email. Using `+aliases` on the existing personal Gmail (or equivalent) avoids creating new mailboxes while keeping the addresses unique to AWS.

- [ ] **Step 1: Decide on two distinct email aliases**

Pick two unique aliases on your existing email address. Suggested:
- Management account root: `<you>+aws-wkx-mgmt@<domain>`
- Platform account root: `<you>+aws-wkx-platform@<domain>`

Both must be globally unique to AWS. AWS treats `+alias` as part of the unique identifier.

- [ ] **Step 2: Send a test email to each alias and confirm receipt**

From any send-capable account, send a one-line test email to both aliases. Confirm both arrive in your primary inbox.

Run on your dev machine to confirm the alias style works:

```bash
echo "Aliases planned:"
echo "  mgmt:     <you>+aws-wkx-mgmt@<domain>"
echo "  platform: <you>+aws-wkx-platform@<domain>"
```

Expected: both emails delivered to the same inbox.

- [ ] **Step 3: Record the aliases in `docs/setup/m0-account-state.md`**

Create the file:

```markdown
# M0 Account State

> Immutable identifiers established during M0. Used by M1 Terraform.

## Email aliases

- Management account root: `<you>+aws-wkx-mgmt@<domain>`
- Platform account root: `<you>+aws-wkx-platform@<domain>`

## AWS account IDs

- Management account: TBD (Task 2)
- Platform account: TBD (Task 5)

## IAM Identity Center

- IdC instance ARN: TBD (Task 6)
- IdC region: TBD (Task 6)
- SSO start URL: TBD (Task 6)
- Permission set name: TBD (Task 7)

## Cloudflare

- Account email: TBD (Task 9)
- Account ID: TBD (Task 9)
```

- [ ] **Step 4: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record account aliases skeleton"
```

---

## Task 2: Create AWS management account

**Files:** none.

**Why:** This will be the new Organization's management account — the security boundary that owns the org structure. It will hold no workloads.

This task is a manual browser flow. Verifications below confirm completion.

- [ ] **Step 1: Open the AWS sign-up page in an incognito window**

Open https://portal.aws.amazon.com/billing/signup in an **incognito / private** window so existing AWS sessions do not interfere.

- [ ] **Step 2: Sign up with the management alias**

Use email: `<you>+aws-wkx-mgmt@<domain>` (from Task 1). Choose a strong, unique root password (store in a password manager).

Walk through:
- Account name: `wkx-mgmt`
- Contact info: personal/individual
- Billing: payment method (charges will be ~$0 until M2)
- Phone verification (SMS or voice)
- Support plan: **Basic** (free)

- [ ] **Step 3: Wait for activation email and confirm sign-in**

Activation typically completes within minutes (occasionally up to 24 hours). When ready, sign in at https://console.aws.amazon.com/ as the root user.

Run to find the account ID once signed in:

```bash
# In the AWS console: top-right account menu → "Account ID" — it's a 12-digit number.
# Record it for the next step.
```

- [ ] **Step 4: Record the management account ID**

Edit `docs/setup/m0-account-state.md`. Replace the `Management account: TBD` line with the actual 12-digit ID:

```markdown
- Management account: 123456789012
```

- [ ] **Step 5: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record management account id"
```

---

## Task 3: Secure the management account root

**Files:** none.

**Why:** The management account holds keys to delete every other account in the org. Root MFA, locked-away credentials, and billing alerts are non-negotiable.

- [ ] **Step 1: Enable MFA on the root user**

In the AWS console (signed in as root):
- Top-right account menu → **Security credentials**
- Section "Multi-factor authentication (MFA)" → **Assign MFA device**
- **Strongly preferred:** a hardware key (YubiKey). Acceptable: a TOTP app (Authy, 1Password, Google Authenticator) — record recovery codes offline.
- Name the device (e.g. `wkx-mgmt-yubikey-1`)

- [ ] **Step 2: Verify MFA enforcement**

Sign out of the console. Sign back in as root. Confirm the MFA prompt appears after the password.

- [ ] **Step 3: Set alternate account contacts**

In the console: account menu → **Account** → **Alternate contacts**. Set:
- Billing contact (your email)
- Operations contact (your email)
- Security contact (your email)

These ensure AWS can reach you about urgent issues without hitting only the root inbox.

- [ ] **Step 4: Create a $10/mo budget alert**

Even though M0–M1 spend should be ~$0, a small budget catches surprises during account setup.

In the console: **Billing & Cost Management** → **Budgets** → **Create budget**:
- Budget type: Cost budget
- Period: Monthly
- Amount: USD $10
- Email: your primary email
- Alert threshold: 80% actual

- [ ] **Step 5: Verify the budget exists**

Run on your dev machine (you'll set up CLI access in Task 11; for now the console suffices):

In the console, **Budgets** page lists "Wkx-Mgmt-Initial-Budget" (or whatever name you gave it).

Expected: budget visible.

- [ ] **Step 6: Lock root credentials away**

Store the root password and MFA recovery codes in a password manager (or a sealed envelope offline). You will not use root again unless you need to perform an action only root can do (rare).

No commit — these are AWS-side actions.

---

## Task 4: Enable AWS Organizations on the management account

**Files:** none.

**Why:** Organizations is the framework that lets you create the platform as a separate member account. It's free.

- [ ] **Step 1: Open Organizations in the management console**

In the AWS console (signed in as root): https://console.aws.amazon.com/organizations/

- [ ] **Step 2: Create the organization**

Click **Create an organization**. Choose:
- Feature set: **All features** (default)

Wait for confirmation that the org is created. AWS will email the management account confirming.

- [ ] **Step 3: Verify the organization exists from the CLI**

You can't run this until Task 11, but you can verify in the console now:

In the console, **AWS Organizations** dashboard shows:
- Organization ID (starts with `o-`)
- One member account (the mgmt account itself, marked as the management account)

Expected: org dashboard loads, mgmt account is the only listed member.

No commit yet — the org ID is not used by Terraform until M1, and even then we likely don't need it (we operate at member-account level).

---

## Task 5: Create the platform member account

**Files:** `docs/setup/m0-account-state.md`.

**Why:** The platform's compute/network/data live in this account, fully isolated from the management account.

- [ ] **Step 1: In the Organizations console, click "Add an AWS account" → "Create an AWS account"**

Fields:
- AWS account name: `wkx-platform`
- Email address of the account's owner: `<you>+aws-wkx-platform@<domain>` (from Task 1)
- IAM role name (in the new account, assumable from mgmt): leave default `OrganizationAccountAccessRole`

Click **Create AWS account**. Provisioning takes a couple of minutes.

- [ ] **Step 2: Wait for account creation to complete**

Refresh the Organizations dashboard until the new account appears with status "Active" and an account ID.

- [ ] **Step 3: Record the platform account ID**

Edit `docs/setup/m0-account-state.md`. Replace `Platform account: TBD` with the 12-digit ID.

- [ ] **Step 4: Verify the new account received its welcome email**

Check the platform alias inbox for the AWS welcome message. (You won't sign in to the new account directly — you'll access it via SSO from Task 8 onward.)

- [ ] **Step 5: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record platform account id"
```

---

## Task 6: Enable IAM Identity Center

**Files:** `docs/setup/m0-account-state.md`.

**Why:** IdC is how you sign in day-to-day. The root user is reserved for emergencies. IdC handles user, permission set, and account assignment.

- [ ] **Step 1: Open IAM Identity Center in the management console**

Console: https://console.aws.amazon.com/singlesignon/

Make sure the AWS region selector (top-right) is set to **ap-southeast-2 (Sydney)** — IdC is regional, and we want it co-located with the platform compute.

- [ ] **Step 2: Enable IAM Identity Center**

Click **Enable**. Choose:
- Identity source: **Identity Center directory** (the default, built-in store)

Wait for the service to provision (~1 minute).

- [ ] **Step 3: Note the SSO start URL and instance ARN**

After enablement, the IdC dashboard shows:
- AWS access portal URL (looks like `https://d-xxxxxxxxxx.awsapps.com/start`)
- Instance ARN (visible under **Settings**)

Copy both.

- [ ] **Step 4: Update `docs/setup/m0-account-state.md`**

Replace TBDs with the real values:

```markdown
- IdC instance ARN: arn:aws:sso:::instance/ssoins-...
- IdC region: ap-southeast-2
- SSO start URL: https://d-xxxxxxxxxx.awsapps.com/start
```

- [ ] **Step 5: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record idc instance details"
```

---

## Task 7: Create IdC user and assign to the platform account

**Files:** `docs/setup/m0-account-state.md`.

**Why:** Day-to-day access happens via this user, with a permission set scoped to the platform account.

- [ ] **Step 1: Create the user**

In IdC console → **Users** → **Add user**:
- Username: e.g. `alice` (use what suits you)
- Email: your primary email (NOT the +aws-wkx aliases — this is your day-to-day login)
- First/last name
- Display name

Choose: **Send an email to this user with password setup instructions**.

Click **Add user**.

- [ ] **Step 2: Complete the password setup from the invitation email**

Check your primary email for the IdC invitation. Follow the link, set a strong password, and configure MFA on this user too.

- [ ] **Step 3: Use the AWS-managed `AdministratorAccess` permission set**

In IdC console → **Permission sets** → **Create permission set**:
- Type: **Predefined permission set** → `AdministratorAccess`
- Name: `AdministratorAccess`
- Session duration: **8 hours**

Click **Create**.

(Tighter permission sets are deferred to the M10 hardening pass. `AdministratorAccess` for a single-purpose member account is acceptable.)

- [ ] **Step 4: Assign the user to the platform account with the permission set**

In IdC console → **AWS accounts** → tick the platform account → **Assign users or groups**:
- Pick the user from Task 7 Step 1
- Pick `AdministratorAccess` permission set

Click **Submit**. IdC provisions an SSO role into the platform account (takes ~30 seconds).

- [ ] **Step 5: Update `docs/setup/m0-account-state.md`**

```markdown
- Permission set name: AdministratorAccess
```

- [ ] **Step 6: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record idc permission set"
```

---

## Task 8: Verify SSO sign-in via the access portal

**Files:** none.

**Why:** Confirms the user → permission set → account chain works end-to-end via the browser before configuring CLI access.

- [ ] **Step 1: Sign out of any AWS console session**

Sign out of root, close incognito windows. Open a fresh browser window.

- [ ] **Step 2: Open the SSO start URL**

Visit the URL recorded in Task 6 (`https://d-xxxxxxxxxx.awsapps.com/start`). Sign in as the IdC user (Task 7), with MFA.

- [ ] **Step 3: Click into the platform account**

The portal should show one card: the platform account, with a `AdministratorAccess` role. Click **Management console** to open the platform account in the AWS console.

- [ ] **Step 4: Confirm the account ID matches**

Top-right of the AWS console: the account ID should match the platform account ID recorded in `docs/setup/m0-account-state.md`. The role should be `AWSReservedSSO_AdministratorAccess_<random>`.

Expected: PASS — you are now signed into the platform account via SSO.

If it fails: re-check Task 7 Step 4 (assignment) and that you're using the correct user.

No commit — verification only.

---

## Task 9: Cloudflare account

**Files:** `docs/setup/m0-account-state.md`.

**Why:** DNS, proxy, WAF, and (in M1) the wildcard cert all hinge on Cloudflare. The zone-scoped API token is created in M1 after the zone exists; M0 just needs the account.

- [ ] **Step 1: Sign up at cloudflare.com**

Use any email — the same primary email as your IdC user is fine. Strong password, store in password manager.

- [ ] **Step 2: Enable 2FA on the Cloudflare account**

Profile → **Authentication** → **Two-Factor Authentication** → enable (TOTP app).

- [ ] **Step 3: Find the account ID**

Cloudflare dashboard → right-side panel shows **Account ID** (a hex string).

- [ ] **Step 4: Update `docs/setup/m0-account-state.md`**

```markdown
- Account email: <your-cloudflare-email>
- Account ID: 0123456789abcdef0123456789abcdef
```

- [ ] **Step 5: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record cloudflare account id"
```

---

## Task 10: Local tooling — verify and install

**Files:** none.

**Why:** M1 needs Terraform, AWS CLI v2 (with SSO support), gh, uv, Docker, and the SSM Session Manager plugin. This task confirms each is present and installs missing ones.

- [ ] **Step 1: Verify mise is installed**

Run:

```bash
mise --version
```

Expected: prints a version (e.g. `2024.x.y`). If not found, install per https://mise.jdx.dev/getting-started.html.

- [ ] **Step 2: Verify or install Docker Desktop**

Run:

```bash
docker --version
docker compose version
```

Expected: both print versions; Docker daemon is running. If not installed: download Docker Desktop for Mac from https://www.docker.com/products/docker-desktop/ (Apple Silicon if Mx-series, Intel otherwise).

- [ ] **Step 3: Verify or install gh (GitHub CLI)**

Run:

```bash
gh --version
gh auth status
```

Expected: version printed, authenticated to github.com. If not installed: `brew install gh` then `gh auth login`.

- [ ] **Step 4: Install AWS CLI v2 via Homebrew if missing**

Run:

```bash
aws --version
```

Expected: prints `aws-cli/2.x.y ...`. If not installed:

```bash
brew install awscli
```

Re-run `aws --version` to confirm v2.

- [ ] **Step 5: Install the SSM Session Manager plugin**

Run:

```bash
session-manager-plugin --version
```

Expected: prints a version. If not installed:

```bash
brew install --cask session-manager-plugin
```

Re-run to confirm.

- [ ] **Step 6: Verify or install Terraform via mise**

Run:

```bash
terraform --version
```

Expected: prints a version (any 1.x is fine for now; M1 will pin a specific version). If missing:

```bash
mise use --global terraform@latest
terraform --version
```

- [ ] **Step 7: Verify uv is on PATH**

Run:

```bash
uv --version
```

Expected: prints a version. If not installed:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Re-source shell, re-run `uv --version`.

- [ ] **Step 8: Document tool versions**

Append to `docs/setup/m0-account-state.md`:

```markdown
## Local tool versions (at M0 completion)

```
mise --version         → <output>
docker --version       → <output>
docker compose version → <output>
gh --version           → <output>
aws --version          → <output>
session-manager-plugin --version → <output>
terraform --version    → <output>
uv --version           → <output>
```
```

Replace `<output>` with the actual one-line output of each command.

- [ ] **Step 9: Commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): record local tool versions"
```

---

## Task 11: Configure AWS CLI SSO profile

**Files:** `~/.aws/config` (local-only; not in repo).

**Why:** Day-to-day terminal access uses this profile. M1 Terraform reads credentials via `aws sso login`.

- [ ] **Step 1: Run `aws configure sso` with these answers**

Run:

```bash
aws configure sso
```

Answer the prompts using the values from `docs/setup/m0-account-state.md`:

- SSO session name: `wkx`
- SSO start URL: (the SSO start URL from Task 6)
- SSO region: `ap-southeast-2`
- SSO registration scopes: leave default (`sso:account:access`)

A browser window opens. Sign in as the IdC user (Task 7), authorize the device.

After auth completes, the CLI lists accessible accounts. Pick the platform account, then the `AdministratorAccess` role.

- Default client region: `ap-southeast-2`
- Default output format: `json`
- Profile name: `wkx-platform`

- [ ] **Step 2: Verify the profile is set up**

Run:

```bash
cat ~/.aws/config
```

Expected: shows a `[sso-session wkx]` block and a `[profile wkx-platform]` block referencing it.

- [ ] **Step 3: Confirm credentials work**

Run:

```bash
aws sts get-caller-identity --profile wkx-platform
```

Expected output:

```json
{
    "UserId": "AROA...:alice",
    "Account": "<platform-account-id>",
    "Arn": "arn:aws:sts::<platform-account-id>:assumed-role/AWSReservedSSO_AdministratorAccess_<random>/alice"
}
```

The `Account` field must match the platform account ID from `docs/setup/m0-account-state.md`. If it does not, you have a profile mismatch — re-run `aws configure sso`.

- [ ] **Step 4: Set the default profile in your shell**

Add this line to your shell rc (e.g. `~/.zshrc`):

```bash
export AWS_PROFILE=wkx-platform
```

Reload: `source ~/.zshrc` (or open a new terminal).

- [ ] **Step 5: Verify default-profile flow**

Run:

```bash
aws sts get-caller-identity
```

Expected: same output as Step 3, but without `--profile wkx-platform`. Account ID matches platform account.

No commit — `~/.aws/config` is local-only.

---

## Task 12: Final hands-on verification

**Files:** none.

**Why:** This is the M0 deliverable: prove the four foundational checks pass, exactly as the design promises.

- [ ] **Step 1: Run the four hands-on commands**

Run from the repo root:

```bash
echo "--- terraform ---"
terraform --version

echo "--- docker ---"
docker --version
docker compose version

echo "--- aws sts ---"
aws sts get-caller-identity

echo "--- gh ---"
gh auth status
```

Expected:
- `terraform --version` prints a version, no errors
- `docker --version` and `docker compose version` print versions
- `aws sts get-caller-identity` returns the platform account ID and the `AWSReservedSSO_AdministratorAccess_*` role ARN
- `gh auth status` reports authenticated to github.com

If any of these fail: revisit the relevant earlier task. Don't proceed to M1 with a partially completed M0.

- [ ] **Step 2: Re-verify SSO portal sign-in still works**

Open the SSO start URL (from `docs/setup/m0-account-state.md`) in a fresh browser tab. Sign in. Click into the platform account. Confirm the AWS console loads with the platform account ID.

- [ ] **Step 3: Mark M0 complete**

Append a completion banner to `docs/setup/m0-account-state.md`:

```markdown
## M0 status

- M0 completed: 2026-05-01 (or actual completion date)
- All hands-on verifications passed
- Ready for M1: Networking + DNS skeleton (Terraform)
```

- [ ] **Step 4: Final commit**

```bash
git add docs/setup/m0-account-state.md
git commit -m "docs(m0): complete — all prerequisites verified"
```

---

## Self-Review

**Spec coverage:** Every M0 deliverable listed in `ROADMAP.md` maps to a task here:

- Fresh AWS management account → Task 2
- AWS Organizations enabled → Task 4
- Platform member account → Task 5
- IAM Identity Center + permission set → Tasks 6, 7
- Cloudflare account exists → Task 9
- Local tools installed: Terraform, Docker Desktop, mise/uv, GitHub CLI → Task 10 (also covers AWS CLI v2 + SSM plugin which the spec assumes implicitly)
- Hands-on artifact: SSO + `terraform/docker/aws sts` working → Task 12

**Placeholder scan:** No "TBD"/"TODO"/"implement later" placeholders remain in step bodies. The `docs/setup/m0-account-state.md` skeleton uses TBDs as fill-in fields — those are intentional and removed by later tasks.

**Type consistency:** No code types here. Names that recur across tasks (`wkx`, `wkx-platform`, `wkx-mgmt`, `AdministratorAccess`, alias formats) are consistent.

**Cross-task references checked:**
- Task 7 references the user created in Task 7 Step 1 — internally consistent.
- Task 11 reads from values written by Tasks 5, 6 — consistent.
- Task 12 verifies tools installed in Task 10 and SSO from Task 11 — consistent.

**Known limitation:** Task 2 (AWS account signup) requires phone verification by AWS, which sometimes takes hours. If verification is delayed, the entire plan stalls until activation. This is unavoidable.

**No external Terraform / IaC yet** — all happens at M1. Anyone executing this plan should resist the urge to start writing Terraform here; it belongs in M1 where the state backend is bootstrapped.
