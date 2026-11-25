# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5.
# Keep state encryption separate from workload keys and retain a controlled recovery path.

data "aws_iam_policy_document" "terraform_state_key" {
  # DESIGN: account recovery enables controlled IAM delegation; named key administrators are separate.
  statement {
    sid       = "AccountRecoveryAndIAMDelegation"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid = "NamedKeyAdministrators"
    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
      "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
      "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = sort(tolist(var.key_administrator_role_arns))
    }
  }

  statement {
    sid       = "BackendCryptographyThroughRegionalS3"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = local.backend_role_arns
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }

    # S3 Bucket Keys use the bucket ARN, rather than an individual state-object ARN, as context.
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [local.state_bucket_arn]
    }
  }

  statement {
    sid       = "BackendKeyMetadata"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = local.backend_role_arns
    }
  }
}

resource "aws_kms_key" "terraform_state" {
  description              = "StratHost Terraform state encryption"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  multi_region             = false
  policy                   = data.aws_iam_policy_document.terraform_state_key.json
  tags                     = { Name = "strathost-shared-euw1-kms-terraform-state" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/strathost/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}
