terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket supplied via -backend-config (see backend.hcl.example)
  }
}

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
