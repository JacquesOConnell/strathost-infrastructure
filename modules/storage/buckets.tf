# Plan section 11: each bucket has a separate purpose and a clear resource name.

resource "aws_s3_bucket" "workload_exports" {
  bucket        = "${local.resource_prefix}-backup-${var.expected_account_id}"
  force_destroy = false
  tags = merge(local.tags, {
    Name               = "${local.resource_prefix}-backup-${var.expected_account_id}"
    DataClassification = "Confidential"
  })
}

resource "aws_s3_bucket" "alb_access_logs" {
  bucket        = "${local.resource_prefix}-alb-logs-${var.expected_account_id}"
  force_destroy = false
  tags = merge(local.tags, {
    Name               = "${local.resource_prefix}-alb-logs-${var.expected_account_id}"
    DataClassification = "Internal"
  })
}

resource "aws_s3_bucket" "origin_trust" {
  count = var.enable_origin_trust ? 1 : 0

  bucket        = "${local.resource_prefix}-origin-trust-${var.expected_account_id}"
  force_destroy = false
  tags = merge(local.tags, {
    Name               = "${local.resource_prefix}-origin-trust-${var.expected_account_id}"
    DataClassification = "Internal"
  })
}

resource "aws_s3_bucket_public_access_block" "workload" {
  for_each = local.bucket_ids

  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "workload" {
  for_each = local.bucket_ids

  bucket = each.value
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "workload" {
  for_each = local.bucket_ids

  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

# Exports use KMS; ALB logs and public CA files use the planned SSE-S3 encryption.
resource "aws_s3_bucket_server_side_encryption_configuration" "workload_exports" {
  bucket = aws_s3_bucket.workload_exports.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.exports_kms_key_arn
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "origin_trust" {
  count = var.enable_origin_trust ? 1 : 0

  bucket = aws_s3_bucket.origin_trust[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "workload_exports" {
  bucket = aws_s3_bucket.workload_exports.id
  rule {
    id     = "object-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = var.environment == "prod" ? 30 : 2
    }
    noncurrent_version_expiration {
      noncurrent_days = var.environment == "prod" ? 30 : 2
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  rule {
    id     = "expired-delete-markers"
    status = "Enabled"
    filter {}
    expiration {
      expired_object_delete_marker = true
    }
  }
  depends_on = [aws_s3_bucket_versioning.workload]
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  rule {
    id     = "object-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = var.environment == "prod" ? 90 : 14
    }
    noncurrent_version_expiration {
      noncurrent_days = var.environment == "prod" ? 90 : 14
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  rule {
    id     = "expired-delete-markers"
    status = "Enabled"
    filter {}
    expiration {
      expired_object_delete_marker = true
    }
  }
  depends_on = [aws_s3_bucket_versioning.workload]
}

resource "aws_s3_bucket_lifecycle_configuration" "origin_trust" {
  count = var.enable_origin_trust ? 1 : 0

  bucket = aws_s3_bucket.origin_trust[0].id
  rule {
    id     = "object-retention"
    status = "Enabled"
    filter {}
    # Keep the current CA bundle; only old versions expire.
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  rule {
    id     = "expired-delete-markers"
    status = "Enabled"
    filter {}
    expiration {
      expired_object_delete_marker = true
    }
  }
  depends_on = [aws_s3_bucket_versioning.workload]
}

# Plan 15.2: upload the public CA bundle, never a private key.
resource "aws_s3_object" "origin_ca_bundle" {
  count = var.enable_origin_trust ? 1 : 0

  bucket                 = aws_s3_bucket.origin_trust[0].id
  key                    = "trust/strathost-origin-ca.pem"
  source                 = var.origin_ca_bundle_file
  source_hash            = try(filesha256(var.origin_ca_bundle_file), null)
  content_type           = "application/x-pem-file"
  server_side_encryption = "AES256"
  tags                   = merge(local.tags, { DataClassification = "Internal" })
  depends_on = [
    aws_s3_bucket_versioning.workload,
    aws_s3_bucket_server_side_encryption_configuration.origin_trust,
    aws_s3_bucket_public_access_block.workload
  ]
}
