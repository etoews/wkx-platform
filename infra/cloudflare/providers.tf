# Reads the token from the CLOUDFLARE_API_TOKEN environment variable.
provider "cloudflare" {}

# This root also writes one AWS resource: the SSM parameter delivering the
# DNS-01 token to the Host (see ssm.tf). Same tag shape as the aws root.
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
