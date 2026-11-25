# Plan section 19: Checkmk reads native AWS metrics through its instance role.
# There are no CloudWatch alarms, dashboards, SNS notifications or CloudWatch agents here.
locals {
  resource_prefix   = "strathost-${var.environment}-euw1"
  export_bucket_arn = "arn:aws:s3:::${local.resource_prefix}-backup-${var.expected_account_id}"
}

data "aws_iam_policy_document" "checkmk_aws" {
  # These inventory/metric APIs require wildcard resources. The region is explicit.
  statement {
    sid = "RegionalInventoryAndMetrics"
    actions = [
      "ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "ec2:DescribeVolumes",
      "ec2:DescribeVolumeStatus", "ec2:DescribeTags", "ec2:DescribeSecurityGroups",
      "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeTags", "rds:DescribeDBInstances", "rds:DescribeEvents",
      "elasticfilesystem:DescribeFileSystems", "elasticfilesystem:DescribeMountTargets",
      "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics",
      "backup:ListBackupJobs", "backup:ListRestoreJobs", "tag:GetResources"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = ["eu-west-1"]
    }
  }

  statement {
    sid       = "DatabaseTags"
    actions   = ["rds:ListTagsForResource"]
    resources = ["arn:aws:rds:eu-west-1:${var.expected_account_id}:db:${local.resource_prefix}-rds-mysql"]
  }

  statement {
    sid       = "BackupRecoveryPointMetadata"
    actions   = ["backup:ListRecoveryPointsByBackupVault"]
    resources = ["arn:aws:backup:eu-west-1:${var.expected_account_id}:backup-vault:${local.resource_prefix}-vault-workloads"]
  }

  # Bucket discovery is account-global; this does not permit object reads.
  statement {
    sid       = "DiscoverAccountBuckets"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  statement {
    sid       = "OwnBucketLocationAndTags"
    actions   = ["s3:GetBucketLocation", "s3:GetBucketTagging"]
    resources = ["arn:aws:s3:::*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.expected_account_id]
    }
  }

  # List metadata is enough to inspect export timestamps; the monitor cannot read backup contents.
  statement {
    sid       = "ExportFreshnessMetadata"
    actions   = ["s3:ListBucket"]
    resources = [local.export_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["sites/*"]
    }
  }
}

resource "aws_iam_role_policy" "checkmk_aws" {
  name   = "${local.resource_prefix}-policy-checkmk-monitoring"
  role   = var.checkmk_role_name
  policy = data.aws_iam_policy_document.checkmk_aws.json
}
