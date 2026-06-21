variable "cloudflare_account_id" {
  description = "Cloudflare account ID. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string
}

variable "apps_apex" {
  description = "Apex domain for Mode-3 apps."
  type        = string
  default     = "wkx.dev"
}
