# Plan 2/5: never select the independent development lab account implicitly.
provider "aws" {
  region              = "eu-west-1"
  allowed_account_ids = [var.expected_account_id]
}
data "aws_caller_identity" "current" {}

locals {
  resource_prefix = "strathost-${var.environment}-euw1"
  site_posix_ids = {
    public_wordpress   = 10001
    secure_wordpress   = 10002
    internal_wordpress = 10003
  }
  tags = {
    Project            = "StratHost", Application = "WordPressHosting", Environment = var.environment,
    ManagedBy          = "Terraform", Owner = "Infrastructure", BusinessUnit = "StratHost",
    Repository         = "strathost-infrastructure", CostCenter = var.cost_center,
    DataClassification = "Confidential", Criticality = var.environment == "prod" ? "High" : "Standard",
    BackupPolicy       = "none"
  }
}
