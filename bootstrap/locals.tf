# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 4 and 5.
# Use deterministic names and mandatory tags; shared state serves several environment keys.

locals {
  state_bucket_name = "strathost-tfstate-${var.expected_account_id}-euw1"
  state_bucket_arn  = "arn:${data.aws_partition.current.partition}:s3:::${local.state_bucket_name}"
  account_root_arn  = "arn:${data.aws_partition.current.partition}:iam::${var.expected_account_id}:root"

  required_tags = merge(var.additional_tags, {
    Project            = "StratHost"
    Application        = "WordPressHosting"
    Environment        = "shared"
    ManagedBy          = "Terraform"
    Owner              = "Infrastructure"
    BusinessUnit       = "StratHost"
    Repository         = "strathost-infrastructure"
    CostCenter         = var.cost_center
    DataClassification = "Confidential"
    Criticality        = "High"
    BackupPolicy       = "none"
  })

  backend_role_arns = distinct([for access in values(var.backend_access) : access.role_arn])
}
