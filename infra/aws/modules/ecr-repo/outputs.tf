output "repository_name" {
  description = "ECR repository name (wkx/<service>)."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "ECR repository URL for docker login / push / pull."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "image_tag_mutability" {
  description = "Tag mutability (invariant: IMMUTABLE). Exposed so invariant tests can assert it after the migration into this module."
  value       = aws_ecr_repository.this.image_tag_mutability
}

output "scan_on_push" {
  description = "Whether images are scanned on push (invariant: true)."
  value       = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
}

output "lifecycle_policy" {
  description = "The ECR lifecycle policy document (JSON). Plan-known, so invariant tests can assert the 30-day expiry and untagged-cleanup rules."
  value       = local.lifecycle_policy
}

output "ci_role_arn" {
  description = "ARN of the CI push/deploy role, or null when the module was instantiated without a github_repo."
  value       = local.create_ci_role ? aws_iam_role.ci[0].arn : null
}

output "ci_role_name" {
  description = "Name of the CI push/deploy role, or null when no CI role was created."
  value       = local.create_ci_role ? aws_iam_role.ci[0].name : null
}

output "ci_subject" {
  description = "The exact OIDC sub the CI role trusts (repo:etoews/<repo>:ref:refs/heads/main), or null when no CI role was created. Derived only from github_repo, so it is plan-known for invariant tests."
  value       = local.ci_subject
}

output "ci_role_policy" {
  description = "The CI role's inline permission document (JSON), or null when no CI role was created. Built from account/region/service/bucket-name so it is plan-known for invariant tests (F-001: never references the state bucket)."
  value       = local.ci_role_policy
}
