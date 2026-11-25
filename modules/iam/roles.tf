# Plan 9: separate machine roles. No IAM users or long-lived access keys.
# Runtime resource policies are attached by the composition root once resource ARNs exist.
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

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "docker" {
  name               = "${local.resource_prefix}-role-docker"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = merge(local.tags, { Name = "${local.resource_prefix}-role-docker" })
}
resource "aws_iam_role" "vpn" {
  name               = "${local.resource_prefix}-role-vpn"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = merge(local.tags, { Name = "${local.resource_prefix}-role-vpn" })
}
resource "aws_iam_role" "checkmk" {
  name               = "${local.resource_prefix}-role-checkmk"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = merge(local.tags, { Name = "${local.resource_prefix}-role-checkmk" })
}
resource "aws_iam_instance_profile" "docker" {
  name = "${local.resource_prefix}-profile-docker"
  role = aws_iam_role.docker.name
  tags = merge(local.tags, { Name = "${local.resource_prefix}-profile-docker" })
}
resource "aws_iam_instance_profile" "vpn" {
  name = "${local.resource_prefix}-profile-vpn"
  role = aws_iam_role.vpn.name
  tags = merge(local.tags, { Name = "${local.resource_prefix}-profile-vpn" })
}
resource "aws_iam_instance_profile" "checkmk" {
  name = "${local.resource_prefix}-profile-checkmk"
  role = aws_iam_role.checkmk.name
  tags = merge(local.tags, { Name = "${local.resource_prefix}-profile-checkmk" })
}

# AWS-maintained baseline for SSM agent control channels; workload access is separate.
resource "aws_iam_role_policy_attachment" "docker_ssm" {
  role       = aws_iam_role.docker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "vpn_ssm" {
  role       = aws_iam_role.vpn.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "checkmk_ssm" {
  role       = aws_iam_role.checkmk.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "backup_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "backup" {
  name               = "${local.resource_prefix}-role-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
  tags               = merge(local.tags, { Name = "${local.resource_prefix}-role-backup" })
}
# Explicit managed-policy exception: AWS Backup's multi-service backup operations.
# This is not attached to any EC2 profile, operator or recovery identity.
resource "aws_iam_role_policy_attachment" "backup_service" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
