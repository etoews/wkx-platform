terraform {
  backend "s3" {
    key          = "mgmt/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
    # bucket and profile supplied via -backend-config (see backend.hcl.example).
    # The state bucket lives in the platform account, so the backend
    # authenticates as wkx-platform while the provider runs as wkx-mgmt.
  }
}
