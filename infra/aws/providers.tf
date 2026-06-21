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
