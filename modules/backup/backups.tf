# Plan 18: explicit EC2/EFS selection, not tags mistaken for backup coverage.
# RDS native automated backups remain in database; do not duplicate that schedule here.
locals {
  resource_prefix = "strathost-${var.environment}-euw1"
  tags = merge(var.additional_tags, {
    Project            = "StratHost", Application = "WordPressHosting", Environment = var.environment,
    ManagedBy          = "Terraform", Owner = "Infrastructure", BusinessUnit = "StratHost",
    Repository         = "strathost-infrastructure", CostCenter = var.cost_center,
    DataClassification = "Confidential", Criticality = var.environment == "prod" ? "High" : "Standard",
    BackupPolicy       = "workloads-daily"
  })
}
resource "aws_backup_vault" "workloads" {
  name          = "${local.resource_prefix}-vault-workloads"
  kms_key_arn   = var.backup_kms_key_arn
  force_destroy = false
  tags          = merge(local.tags, { Name = "${local.resource_prefix}-vault-workloads" })
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_backup_plan" "workloads" {
  name = "${local.resource_prefix}-plan-workloads-daily"
  tags = merge(local.tags, { Name = "${local.resource_prefix}-plan-workloads-daily" })
  rule {
    rule_name                    = "daily-ec2-and-efs"
    target_vault_name            = aws_backup_vault.workloads.name
    schedule                     = "cron(0 1 * * ? *)"
    schedule_expression_timezone = "Etc/UTC"
    start_window                 = 60
    completion_window            = 180
    recovery_point_tags          = local.tags
    lifecycle {
      delete_after = var.environment == "prod" ? 14 : 2
    }
  }
}
resource "aws_backup_selection" "workloads" {
  name         = "${local.resource_prefix}-selection-workloads"
  plan_id      = aws_backup_plan.workloads.id
  iam_role_arn = var.backup_role_arn
  resources    = concat(var.instance_arns, [var.efs_file_system_arn])
}
