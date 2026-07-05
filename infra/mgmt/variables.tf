variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile for the management account (scoped wkx-budgets permission set, not AdministratorAccess). The backend has its own profile; see backend.hcl.example."
  type        = string
  default     = "wkx-mgmt"
}

variable "mgmt_account_id" {
  description = "Management AWS account ID. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.mgmt_account_id))
    error_message = "mgmt_account_id must be a 12-digit AWS account ID."
  }
}

variable "alert_email" {
  description = "Email address that receives budget alerts. Real value lives in m0-account-state.local.md; pass via -var-file."
  type        = string
}

variable "org_budget_limit_usd" {
  description = "Monthly consolidated budget in USD. 45 covers the M2 on-demand burn-in; drop to about 30 once the M10 Savings Plan lands."
  type        = number
  default     = 45
}
