terraform {
  backend "s3" {
    key          = "aws/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket supplied via -backend-config (see backend.hcl.example)
  }
}
