# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 11.1.
# Limit client transport and separate export writing, recovery reading and ALB log delivery.

# DESIGN: direct AWS service calls can have redacted transport context; exempting them grants no access.
data "aws_iam_policy_document" "tls_only" {
  for_each = local.bucket_ids

  statement {
    sid       = "DenyInsecureClientTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${each.value}", "arn:aws:s3:::${each.value}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
    condition {
      test     = "Bool"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "workload_exports" {
  source_policy_documents = [data.aws_iam_policy_document.tls_only["workload_exports"].json]

  statement {
    sid       = "WriteDeclaredSiteExports"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [for prefix in local.export_prefixes : "${local.export_bucket_arn}/${prefix}*"]
    principals {
      type        = "AWS"
      identifiers = [var.docker_runtime_role_arn]
    }
  }

  statement {
    sid       = "ListDeclaredSiteExportPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [local.export_bucket_arn]
    principals {
      type        = "AWS"
      identifiers = [var.docker_runtime_role_arn, var.recovery_role_arn]
    }
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for prefix in local.export_prefixes : "${prefix}*"]
    }
  }

  statement {
    sid       = "ReadExportsForApprovedRecovery"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [for prefix in local.export_prefixes : "${local.export_bucket_arn}/${prefix}*"]
    principals {
      type        = "AWS"
      identifiers = [var.recovery_role_arn]
    }
  }

  statement {
    # The Docker role is shared by all hosts; only Docker01 will schedule exports (plan 10.2 and 11.1).
    sid       = "DenyUnexpectedExportWriters"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${local.export_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.docker_runtime_role_arn]
    }
  }

  statement {
    sid       = "DenyExportReadsOutsideRecoveryRole"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${local.export_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.recovery_role_arn]
    }
  }

  statement {
    sid       = "DenyExplicitWrongExportEncryption"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.export_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["false"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid       = "DenyExplicitWrongExportKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.export_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = ["false"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [var.exports_kms_key_arn]
    }
  }

  statement {
    sid       = "DenyCustomerProvidedExportKeys"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.export_bucket_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption-customer-algorithm"
      values   = ["false"]
    }
  }
}

# DESIGN: delivery writes only the three visibility/account paths; do not force SSE-KMS on this bucket.
data "aws_iam_policy_document" "alb_access_logs" {
  source_policy_documents = [data.aws_iam_policy_document.tls_only["alb_access_logs"].json]

  statement {
    sid     = "AWSLoadBalancerAccessLogDelivery"
    actions = ["s3:PutObject"]
    resources = [for visibility in ["public", "secure", "internal"] :
      "${aws_s3_bucket.alb_access_logs.arn}/alb/${visibility}/AWSLogs/${var.expected_account_id}/*"
    ]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "workload_exports" {
  bucket = aws_s3_bucket.workload_exports.id
  policy = data.aws_iam_policy_document.workload_exports.json
  depends_on = [
    aws_s3_bucket_public_access_block.workload,
    aws_s3_bucket_ownership_controls.workload,
    aws_s3_bucket_server_side_encryption_configuration.workload_exports
  ]
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = data.aws_iam_policy_document.alb_access_logs.json
  depends_on = [
    aws_s3_bucket_public_access_block.workload,
    aws_s3_bucket_ownership_controls.workload,
    aws_s3_bucket_server_side_encryption_configuration.alb_access_logs
  ]
}

resource "aws_s3_bucket_policy" "origin_trust" {
  count = var.enable_origin_trust ? 1 : 0

  bucket     = aws_s3_bucket.origin_trust[0].id
  policy     = data.aws_iam_policy_document.tls_only["origin_trust"].json
  depends_on = [aws_s3_bucket_public_access_block.workload, aws_s3_bucket_ownership_controls.workload]
}
