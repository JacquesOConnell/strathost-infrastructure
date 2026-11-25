# Plan 8/19: traffic diagnostics, not a second monitoring/notification platform.
resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/aws/vpc/${local.resource_prefix}/flow"
  retention_in_days = var.environment == "prod" ? 90 : 14
  kms_key_id        = var.logs_kms_key_arn
  tags = {
    Name        = "${local.resource_prefix}-logs-vpc-flow", Project = "StratHost", Environment = var.environment,
    ManagedBy   = "Terraform", CostCenter = var.cost_center, Owner = "Infrastructure", BusinessUnit = "StratHost",
    Application = "WordPressHosting", Repository = "strathost-infrastructure", DataClassification = "Confidential",
    Criticality = var.environment == "prod" ? "High" : "Standard", BackupPolicy = "none"
  }
}
data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.expected_account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ec2:eu-west-1:${var.expected_account_id}:vpc-flow-log/*"]
    }
  }
}
resource "aws_iam_role" "flow_logs" {
  name               = "${local.resource_prefix}-role-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust.json
  tags               = merge(aws_cloudwatch_log_group.vpc_flow.tags, { Name = "${local.resource_prefix}-role-flow-logs" })
}
data "aws_iam_policy_document" "flow_logs_delivery" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }
  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "flow_logs_delivery" {
  name   = "${local.resource_prefix}-policy-flow-logs"
  role   = aws_iam_role.flow_logs.name
  policy = data.aws_iam_policy_document.flow_logs_delivery.json
}
resource "aws_flow_log" "vpc" {
  vpc_id                   = var.vpc_id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 600
  tags                     = merge(aws_cloudwatch_log_group.vpc_flow.tags, { Name = "${local.resource_prefix}-vpc-flow" })
  depends_on               = [aws_iam_role_policy.flow_logs_delivery]
}
