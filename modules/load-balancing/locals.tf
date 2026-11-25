# Plan 16: three independent ALBs, never ALB-to-ALB chaining.
locals {
  resource_prefix = "strathost-${var.environment}-euw1"
  tags = merge(var.additional_tags, {
    Project            = "StratHost", Application = "WordPressHosting", Environment = var.environment,
    ManagedBy          = "Terraform", Owner = "Infrastructure", BusinessUnit = "StratHost",
    Repository         = "strathost-infrastructure", CostCenter = var.cost_center,
    DataClassification = "Confidential", Criticality = var.environment == "prod" ? "High" : "Standard",
    BackupPolicy       = "none"
  })
}
