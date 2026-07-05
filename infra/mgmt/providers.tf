provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = "wkx"
      ManagedBy = "terraform"
      Repo      = "wkx-platform"
    }
  }
}
