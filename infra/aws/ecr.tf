# Image repositories for the platform's own images, named wkx/<service> to
# match the path-style /wkx/<service>/... namespacing of SSM parameters and
# log groups. Per-service resources: Service tag, no Env (images are
# per-commit; the env decides which tag deploys where). Lifecycle policies
# are an M6 deliverable with the ecr-repo module, which these migrate into.
resource "aws_ecr_repository" "caddy" {
  name                 = "wkx/caddy"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "wkx/caddy", Service = "caddy" }
}

resource "aws_ecr_repository" "hello" {
  name                 = "wkx/hello"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "wkx/hello", Service = "hello" }
}
