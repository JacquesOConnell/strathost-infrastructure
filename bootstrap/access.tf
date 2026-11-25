# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5.
# Give each existing backend role access only to its assigned state and lock objects.

data "aws_iam_policy_document" "terraform_backend" {
  for_each = var.backend_access

  statement {
    sid       = "ListApprovedStateAndLockKeys"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values = sort(concat(
        tolist(each.value.state_keys),
        [for key in each.value.state_keys : "${key}.tflock"]
      ))
    }
  }

  statement {
    sid       = "ReadAndWriteState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [for key in each.value.state_keys : "${local.state_bucket_arn}/${key}"]
  }

  # DESIGN: native S3 locking needs DeleteObject on .tflock, not on the state file itself.
  statement {
    sid       = "CoordinateNativeS3Locks"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for key in each.value.state_keys : "${local.state_bucket_arn}/${key}.tflock"]
  }

  statement {
    sid       = "UseStateKeyThroughS3"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"]
    resources = [aws_kms_key.terraform_state.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [local.state_bucket_arn]
    }
  }

  statement {
    sid       = "InspectStateKey"
    actions   = ["kms:DescribeKey"]
    resources = [aws_kms_key.terraform_state.arn]
  }
}

# Existing identity ownership stays outside this stack; output the policy-to-role assignment for attachment.
resource "aws_iam_policy" "terraform_backend" {
  for_each = var.backend_access

  name        = "strathost-shared-euw1-policy-backend-${each.key}"
  path        = "/strathost/bootstrap/"
  description = "Access to explicitly assigned StratHost state and S3 lock objects"
  policy      = data.aws_iam_policy_document.terraform_backend[each.key].json
  tags        = { Name = "strathost-shared-euw1-policy-backend-${each.key}" }
}
