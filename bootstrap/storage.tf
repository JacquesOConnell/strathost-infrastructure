# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5.
# Protect infrastructure state with private ownership, versioning, encryption and retained history.

resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = { Name = local.state_bucket_name }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = data.aws_caller_identity.deployment.account_id == var.expected_account_id
      error_message = "Caller account differs from the explicitly approved bootstrap account."
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # DESIGN: expire only old versions; current state and lock objects have no automatic expiry.
  rule {
    id     = "retain-state-history"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  depends_on = [aws_s3_bucket_versioning.terraform_state]
}

data "aws_iam_policy_document" "terraform_state_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Check only explicit headers so legitimate requests can use the bucket encryption defaults.
  statement {
    sid       = "DenyExplicitWrongEncryptionAlgorithm"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_bucket_arn}/*"]

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
    sid       = "DenyExplicitWrongKMSKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_bucket_arn}/*"]

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
      values   = [aws_kms_key.terraform_state.arn]
    }
  }

  statement {
    sid       = "DenyCustomerProvidedEncryptionKeys"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.state_bucket_arn}/*"]

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

  dynamic "statement" {
    for_each = var.backend_access
    content {
      sid       = "ListApprovedPaths${substr(sha256(statement.key), 0, 12)}"
      actions   = ["s3:ListBucket"]
      resources = [local.state_bucket_arn]

      principals {
        type        = "AWS"
        identifiers = [statement.value.role_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "s3:prefix"
        values = sort(concat(
          tolist(statement.value.state_keys),
          [for key in statement.value.state_keys : "${key}.tflock"]
        ))
      }
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state_bucket.json

  depends_on = [
    aws_s3_bucket_public_access_block.terraform_state,
    aws_s3_bucket_ownership_controls.terraform_state,
    aws_s3_bucket_server_side_encryption_configuration.terraform_state
  ]
}
