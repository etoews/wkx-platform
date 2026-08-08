# The hello project bundle: its ECR repository (with a CI role, since hello
# ships from the public wkx-hello repo) and its CloudWatch log group. One .tf
# per project (design spec §5). DNS records live in the cloudflare/ root, so
# this file carries none.
#
# Note on layout: the design sketch put per-project files under a projects/
# directory, but Terraform does not load subdirectories of a root module, so a
# per-project bundle that must be applied in the aws/ root is a flat file here.
module "hello" {
  source = "./modules/ecr-repo"

  service            = "hello"
  github_repo        = "wkx-hello"
  github_owner_id    = "634901"     # github.com/etoews (public, immutable)
  github_repo_id     = "1327570828" # github.com/etoews/wkx-hello (public, immutable)
  oidc_provider_arn  = aws_iam_openid_connect_provider.github.arn
  deploy_bucket_name = aws_s3_bucket.deploy.bucket
}

# Adopt the pre-module repository into the module so it is not destroyed and
# recreated (which would drop every pushed image).
moved {
  from = aws_ecr_repository.hello
  to   = module.hello.aws_ecr_repository.this
}

# Absorbed from logs.tf. The resource address (aws_cloudwatch_log_group.hello)
# and the group name (/wkx/hello/prod) are unchanged, so this is a pure file
# relocation: Terraform sees no change and no moved block is needed (a moved
# block requires the address to change). The awslogs driver and the
# observability invariants keep pointing at the same group.
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/wkx/hello/prod"
  retention_in_days = 7

  tags = { Name = "/wkx/hello/prod", Service = "hello", Env = "prod" }
}
