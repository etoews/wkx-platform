# One GitHub Actions OIDC provider for the whole account. Every wkx-* repo's
# deploy workflow federates through it to assume its own per-project CI role
# (the ecr-repo module builds those roles, scoped to one repo's main ref).
# Account-level, so no env dimension. The thumbprint is left to AWS: since 2023
# AWS validates token.actions.githubusercontent.com against its own trust store,
# so a hardcoded thumbprint would only go stale.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = { Name = "github-actions-oidc" }
}
