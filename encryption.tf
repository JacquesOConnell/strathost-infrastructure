# Plan 9: account delegation enables exact identity grants; it does not grant every role key use.
data "aws_iam_policy_document" "key_base" {
  statement {
    sid       = "EnableAccountIAMPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.expected_account_id}:root"]
    }
  }
  statement {
    sid = "ApprovedKeyAdministration"
    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*",
      "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*", "kms:TagResource",
      "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = var.key_administrator_role_arns
    }
  }
}
data "aws_iam_policy_document" "logs_key" {
  source_policy_documents = [data.aws_iam_policy_document.key_base.json]
  statement {
    sid       = "RegionalLogsForThisDeployment"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.eu-west-1.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:eu-west-1:${var.expected_account_id}:log-group:/aws/rds/instance/${local.resource_prefix}-rds-mysql/*",
        "arn:aws:logs:eu-west-1:${var.expected_account_id}:log-group:/aws/vpc/${local.resource_prefix}/flow"
      ]
    }
  }
}
module "encryption" {
  source      = "./modules/encryption"
  environment = var.environment
  cost_center = var.cost_center
  key_policy_json = {
    ebs     = data.aws_iam_policy_document.key_base.json
    rds     = data.aws_iam_policy_document.key_base.json
    efs     = data.aws_iam_policy_document.key_base.json
    backup  = data.aws_iam_policy_document.key_base.json
    exports = data.aws_iam_policy_document.key_base.json
    secrets = data.aws_iam_policy_document.key_base.json
    logs    = data.aws_iam_policy_document.logs_key.json
  }
}
