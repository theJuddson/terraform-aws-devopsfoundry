output "budget_name" {
  description = "Budget name."
  value       = aws_budgets_budget.this.name
}

output "budget_arn" {
  description = "Budget ARN."
  value       = aws_budgets_budget.this.arn
}
