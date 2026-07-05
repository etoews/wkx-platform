# Budgets live in the management (payer) account: an unfiltered budget there
# sees consolidated spend across the whole organisation, and a LinkedAccount
# filter scopes one down to a single account.

data "aws_caller_identity" "current" {}

locals {
  # Both budgets precondition on this so a wrong AWS profile cannot silently
  # create them in the platform account, where "consolidated" means only that
  # account's own spend.
  running_in_mgmt = data.aws_caller_identity.current.account_id == var.mgmt_account_id
}

# Tripwire: the management account itself runs only Organizations, IdC, and
# billing (all free), so its own spend must stay at zero forever.
resource "aws_budgets_budget" "mgmt_zero_spend" {
  name         = "wkx-mgmt-zero-spend"
  budget_type  = "COST"
  limit_amount = "1.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [var.mgmt_account_id]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 0.01
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = [var.alert_email]
  }

  lifecycle {
    precondition {
      condition     = local.running_in_mgmt
      error_message = "This root must run against the management account; check the AWS profile."
    }
  }
}

# Consolidated monthly spend across every account in the organisation,
# alerting before (80% actual) and at (100% forecasted) the planned limit.
resource "aws_budgets_budget" "org_monthly" {
  name         = "wkx-org-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.org_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }

  lifecycle {
    precondition {
      condition     = local.running_in_mgmt
      error_message = "This root must run against the management account; check the AWS profile."
    }
  }
}
