variable "name" {
  description = "Budget name, unique in the account."
  type        = string
}

variable "monthly_limit" {
  description = "Monthly budget amount."
  type        = number
}

variable "currency" {
  description = "Currency of `monthly_limit`."
  type        = string
  default     = "USD"
}

variable "actual_thresholds_percent" {
  description = "Notify when actual spend this month passes each of these percentages of the limit."
  type        = list(number)
  default     = [80, 100]
}

variable "forecast_thresholds_percent" {
  description = "Notify when forecast spend for the month passes each of these percentages of the limit."
  type        = list(number)
  default     = [100]
}

variable "email_addresses" {
  description = "Addresses to notify (up to 10). AWS Budgets emails them directly; no confirmation is needed."
  type        = list(string)
  default     = []
}

variable "sns_topic_arns" {
  description = "SNS topics to notify (at most one per notification). The topic policy must let budgets.amazonaws.com publish."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.sns_topic_arns) <= 1
    error_message = "AWS Budgets allows one SNS topic per notification."
  }
}

variable "cost_filters" {
  description = "Limit the budget to some costs, for example { TagKeyValue = [\"user:app$my-app\"] } or { Service = [\"Amazon Elastic Compute Cloud - Compute\"] }."
  type        = map(list(string))
  default     = {}
}

variable "tags" {
  description = "Tags for the budget."
  type        = map(string)
  default     = {}
}
