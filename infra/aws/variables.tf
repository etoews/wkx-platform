variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-2"
}

variable "alert_email" {
  description = "Email address for alarm notifications. Real value lives in the gitignored terraform.local.tfvars (invariant 7); same variable name and pattern as infra/mgmt."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a plausible email address."
  }
}
