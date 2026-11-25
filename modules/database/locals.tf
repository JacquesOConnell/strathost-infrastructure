# Plan sections 4 and 13: clear names and ordinary environment-specific values.
locals {
  resource_prefix = "strathost-${var.environment}-euw1"
  db_identifier   = "${local.resource_prefix}-rds-mysql"
  tags = merge(var.additional_tags, {
    Project            = "StratHost"
    Application        = "WordPressHosting"
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Owner              = "Infrastructure"
    BusinessUnit       = "StratHost"
    Repository         = "strathost-infrastructure"
    CostCenter         = var.cost_center
    DataClassification = "Confidential"
    Criticality        = var.environment == "prod" ? "High" : "Standard"
    BackupPolicy       = "rds-native"
  })
}
