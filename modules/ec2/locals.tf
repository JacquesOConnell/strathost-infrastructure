# Plan sections 4 and 14: names and sizing remain easy to read at each resource.
locals {
  resource_prefix = "strathost-${var.environment}-euw1"
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
    BackupPolicy       = "ec2-daily"
  })
}
