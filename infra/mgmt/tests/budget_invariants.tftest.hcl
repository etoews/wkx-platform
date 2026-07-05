# Encodes the budget invariants as plan-time checks against a mocked AWS
# provider (no credentials needed): the zero-spend tripwire stays scoped to
# the management account alone (unfiltered, a payer-account budget sees
# consolidated spend and would always fire), and the consolidated budget
# alerts both before and at the planned limit.

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "111111111111"
    }
  }
}

variables {
  mgmt_account_id = "111111111111"
  alert_email     = "alerts@example.com"
}

run "zero_spend_is_scoped_to_the_mgmt_account" {
  command = plan

  assert {
    condition = anytrue([
      for f in aws_budgets_budget.mgmt_zero_spend.cost_filter :
      f.name == "LinkedAccount" && length(f.values) == 1 && contains(f.values, var.mgmt_account_id)
    ])
    error_message = "The zero-spend budget must filter to the management account only."
  }

  assert {
    condition = anytrue([
      for n in aws_budgets_budget.mgmt_zero_spend.notification :
      n.notification_type == "ACTUAL" && n.threshold_type == "ABSOLUTE_VALUE" && n.threshold == 0.01
    ])
    error_message = "The zero-spend budget must alert on any actual spend above $0.01."
  }
}

run "org_budget_alerts_before_and_at_the_limit" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.org_monthly.cost_filter) == 0
    error_message = "The consolidated budget must stay unfiltered so it sees the whole organisation's spend."
  }

  assert {
    condition = anytrue([
      for n in aws_budgets_budget.org_monthly.notification :
      n.notification_type == "ACTUAL" && n.threshold_type == "PERCENTAGE" && n.threshold == 80
    ])
    error_message = "The consolidated budget must alert at 80% actual spend."
  }

  assert {
    condition = anytrue([
      for n in aws_budgets_budget.org_monthly.notification :
      n.notification_type == "FORECASTED" && n.threshold_type == "PERCENTAGE" && n.threshold == 100
    ])
    error_message = "The consolidated budget must alert at 100% forecasted spend."
  }
}
