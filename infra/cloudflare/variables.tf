variable "cloudflare_account_id" {
  description = "Cloudflare account ID. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string
}

variable "apps_apex" {
  description = "Apex domain for Mode-3 apps."
  type        = string
  default     = "wingkongexchange.dev"
}

variable "region" {
  description = "AWS region for the SSM parameter."
  type        = string
  default     = "ap-southeast-2"
}

variable "host_public_ip" {
  description = "The Host's EIP (aws root output host_public_ip). Real value lives in the local tfvars; pass via -var-file."
  type        = string
}

variable "host_ipv6_address" {
  description = "The Host's pinned IPv6 (aws root output host_ipv6_address). Real value lives in the local tfvars; pass via -var-file."
  type        = string
}
