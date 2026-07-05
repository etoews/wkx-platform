output "zero_spend_budget_name" {
  description = "Tripwire budget: the management account itself must never incur charges."
  value       = aws_budgets_budget.mgmt_zero_spend.name
}

output "org_budget_name" {
  description = "Consolidated monthly budget across all accounts in the organisation."
  value       = aws_budgets_budget.org_monthly.name
}
