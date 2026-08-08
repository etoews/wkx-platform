# M6 infra state: CI/CD

Public-safe template. Real identifiers live in `m6-infra-state.local.md`
(gitignored, never committed).

## What M6 changed
- GitHub Actions OIDC provider, account-level so no env dimension
  (`infra/aws/oidc.tf`): `token.actions.githubusercontent.com`, audience
  `sts.amazonaws.com`, thumbprint left to AWS. Every `wkx-*` repo federates
  through it to assume its own per-project CI role.
- Reusable `ecr-repo` module (`infra/aws/modules/ecr-repo/`): a per-service ECR
  repository (immutable tags, scan-on-push) plus a lifecycle policy (untagged
  swept after 1 day, all images after 30), and OPTIONALLY a per-repo CI role
  when `github_repo` is set. The module takes no `env` input: a repository is
  per-service, and the `<sha>` tag decides which env deploys.
- Platform image repositories via the module: `wkx/caddy` instantiated without
  a `github_repo` (no CI role; the platform builds and pushes its own image at
  M6.1) and `wkx/hello` with a CI role (it ships from the public `wkx-hello`
  repo). Both adopted from their pre-module resources with `moved` blocks, so no
  pushed image is dropped.
- `wkx-ci-hello` CI role: trusts the single OIDC subject
  `repo:etoews/wkx-hello:ref:refs/heads/main` only, and grants exactly three
  things: ECR push to `wkx/hello`, `ssm:SendCommand`, and `s3:PutObject` under
  `deploy/hello/*`. It gets no Terraform state-bucket access at all, so an
  Actions compromise cannot reach the DNS-01 token (F-001, ADR 0024).
- Shared deploy bucket `<DEPLOY_BUCKET>` (`infra/aws/deploy.tf`, ADR 0024):
  name built from the account id at plan time (no literal id in a committed
  file, invariant 7), versioned, AES256 with bucket keys, public access
  blocked, a TLS-only bucket policy, and a 30-day bundle expiry mirroring the
  ECR window. GitHub Actions uploads each bundle to
  `deploy/<service>/<sha>/bundle.tar.gz`.
- Host instance-role read grant (`infra/aws/iam.tf`): the same `wkx-host` role
  gains `s3:GetObject` on `deploy/*` and a `deploy/*`-scoped `s3:ListBucket`, so
  the on-box deploy script pulls each bundle. Never the state bucket, never a
  second role.

## Identifiers (placeholders; real values in the .local.md sibling)
- Deploy bucket: `<DEPLOY_BUCKET>` (`wkx-deploy-<PLATFORM_ACCOUNT_ID>`)
- OIDC provider ARN:
  `arn:aws:iam::<PLATFORM_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`
- hello CI role ARN: `arn:aws:iam::<PLATFORM_ACCOUNT_ID>:role/wkx-ci-hello`
  (this is the value of the `wkx-hello` Actions secret `AWS_DEPLOY_ROLE_ARN`;
  masked in a public repo)
- ECR repositories:
  `<PLATFORM_ACCOUNT_ID>.dkr.ecr.ap-southeast-2.amazonaws.com/wkx/caddy` and
  `.../wkx/hello`

## M6 status
- M6 infra and pipeline code landed on `feat/m6-cicd-pipeline`. The live prod
  deploy is gated on operator steps, tracked as the M6 carry-forward in
  `ROADMAP.md`: applying the M6 Terraform, creating and pushing the public
  `wkx-hello` GitHub repo, setting its `AWS_DEPLOY_ROLE_ARN` secret, the Host
  repo checkout, and the first push-to-main deploy.
- Hands-on artefacts (serving in under two minutes, git-revert rollback) are
  recorded here once the green deploy lands.
