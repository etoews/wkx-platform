# Reusable per-service image repository (design spec §5). It always creates an
# ECR repository (immutable tags, scan-on-push) with a lifecycle policy, and
# OPTIONALLY a CI role: set github_repo and the module builds a role that the
# named repo's main-ref GitHub Actions run can assume via OIDC to push the
# image, send the deploy command, and drop the bundle in its own prefix. The
# role never touches the Terraform state bucket (F-001, ADR 0024).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  create_ci_role = var.github_repo != null

  repository_name = "wkx/${var.service}"

  # Built from account + region rather than aws_ecr_repository.this.arn so the
  # CI policy stays plan-known (testable) even for a brand-new repository.
  repository_arn = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${local.repository_name}"

  # The CI role trusts this repo's main ref only. AWS requires the trust to
  # condition on `sub` (or job_workflow_ref), and GitHub's OIDC `sub` embeds
  # immutable numeric owner/repo IDs (repo:owner@<id>/name@<id>:ref:...). When
  # those IDs are supplied the trust pins the exact sub, so a deleted-and-
  # recreated repo or a reused owner login cannot assume the role; when they are
  # not, the IDs are wildcarded (owner login and repo name still pinned). Either
  # way the ref is anchored to main, so a PR (different ref) cannot assume it.
  ci_owner_seg   = var.github_owner_id != null ? var.github_owner_id : "*"
  ci_repo_seg    = var.github_repo_id != null ? var.github_repo_id : "*"
  ci_sub_pattern = local.create_ci_role ? "repo:etoews@${local.ci_owner_seg}/${var.github_repo}@${local.ci_repo_seg}:ref:refs/heads/main" : null

  ci_assume_role_policy = local.create_ci_role ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubOidcMainRefOnly"
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.ci_sub_pattern
        }
      }
    }]
  }) : null

  # Exactly three grants: ECR push to this repo, ssm send-command, and PutObject
  # under this service's own deploy prefix. No state-bucket access anywhere.
  ci_role_policy = local.create_ci_role ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPushPullThisRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = local.repository_arn
      },
      {
        Sid    = "SsmSendCommand"
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:document/*",
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",
        ]
      },
      {
        Sid    = "SsmReadOwnCommandResult"
        Effect = "Allow"
        Action = [
          "ssm:ListCommandInvocations",
          "ssm:GetCommandInvocation",
        ]
        # Read-only: lets the deploy workflow wait on its own send-command and
        # gate the green tick on the on-box deploy actually succeeding. Neither
        # action supports resource-level scoping, so Resource is *; both expose
        # only command-invocation status and output, never instance control.
        Resource = "*"
      },
      {
        Sid      = "DeployBundlePutOwnPrefix"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${var.deploy_bucket_name}/deploy/${var.service}/*"
      },
    ]
  }) : null

  # One expiry rule plus untagged cleanup. The tagStatus "any" rule must carry
  # the highest rulePriority, so untagged (1) is evaluated before it (2).
  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire all images older than ${var.expire_after_days} days; rollbacks rebuild from git."
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.expire_after_days
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = local.repository_name, Service = var.service }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

resource "aws_iam_role" "ci" {
  count = local.create_ci_role ? 1 : 0

  name               = "wkx-ci-${var.service}"
  assume_role_policy = local.ci_assume_role_policy

  tags = { Name = "wkx-ci-${var.service}", Service = var.service }
}

resource "aws_iam_role_policy" "ci" {
  count = local.create_ci_role ? 1 : 0

  name   = "ci-deploy"
  role   = aws_iam_role.ci[0].id
  policy = local.ci_role_policy
}
