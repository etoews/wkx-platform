# Platform-owned image repositories run through the reusable ecr-repo module,
# named wkx/<service> to match the path-style /wkx/<service>/... namespacing of
# SSM parameters and log groups. The module adds the M6 lifecycle policy
# (30-day expiry plus untagged cleanup). Per-project app repositories live in
# their own files (for example hello.tf); this file holds the platform's own.
#
# caddy is instantiated WITHOUT a github_repo, so it gets no CI role: the
# platform builds and pushes the Caddy image itself (M6.1), not an app repo.
module "caddy" {
  source  = "./modules/ecr-repo"
  service = "caddy"
}

# Adopt the pre-module repository into the module so it is not destroyed and
# recreated (which would drop every pushed image).
moved {
  from = aws_ecr_repository.caddy
  to   = module.caddy.aws_ecr_repository.this
}
