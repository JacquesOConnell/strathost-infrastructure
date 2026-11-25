# Plan 9: create machine identities first, attach exact resource grants once IDs are known.
module "iam" {
  source      = "./modules/iam"
  environment = var.environment
  cost_center = var.cost_center
}

# Empty secret containers only. Populate values outside Terraform with an approved secret workflow.
# No secret-version resources or plaintext secret data sources are used.
resource "aws_secretsmanager_secret" "wordpress" {
  for_each                = local.site_posix_ids
  name                    = "${local.resource_prefix}/wordpress/${each.key}"
  description             = "Site database credentials and shared WordPress salts; populate outside Terraform"
  kms_key_id              = module.encryption.key_arns.secrets
  recovery_window_in_days = 30
  tags                    = merge(local.tags, { Name = "${local.resource_prefix}-secret-${each.key}", Site = each.key })
}
resource "aws_secretsmanager_secret" "vpn" {
  name                    = "${local.resource_prefix}/vpn/server-private-key"
  description             = "WireGuard server private key; generate and populate outside Terraform"
  kms_key_id              = module.encryption.key_arns.secrets
  recovery_window_in_days = 30
  tags                    = merge(local.tags, { Name = "${local.resource_prefix}-secret-vpn-key" })
}

data "aws_iam_policy_document" "docker_runtime" {
  statement {
    sid       = "SiteSecretsOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for secret in aws_secretsmanager_secret.wordpress : secret.arn]
  }
  statement {
    sid       = "DecryptSiteSecretsThroughSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [module.encryption.key_arns.secrets]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.eu-west-1.amazonaws.com"]
    }
  }
  statement {
    sid       = "EFSUploadsThroughApprovedAccessPoints"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [module.storage.efs_file_system_arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [for access_point in module.storage.efs_access_points : access_point.arn]
    }
    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }
  statement {
    sid       = "WriteOnlySiteExports"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [for prefix in values(module.storage.export_prefixes) : "${module.storage.bucket_arns.workload_exports}/${prefix}*"]
  }
  statement {
    sid       = "ListExportPrefixes"
    actions   = ["s3:ListBucket"]
    resources = [module.storage.bucket_arns.workload_exports]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for prefix in values(module.storage.export_prefixes) : "${prefix}*"]
    }
  }
  # Multipart SSE-KMS uploads need Decrypt as well as GenerateDataKey.
  # This key grant does not grant S3 GetObject; the bucket explicitly denies runtime object reads.
  statement {
    sid       = "EncryptExportsThroughS3"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [module.encryption.key_arns.exports]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.eu-west-1.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [module.storage.bucket_arns.workload_exports]
    }
  }
  statement {
    sid       = "ApprovedSSMArtifactReads"
    actions   = ["s3:GetObject"]
    resources = [for arn in var.ssm_artifact_bucket_arns : "${arn}/*"]
  }
}
resource "aws_iam_role_policy" "docker_runtime" {
  name   = "${local.resource_prefix}-policy-docker-runtime"
  role   = module.iam.role_names.docker
  policy = data.aws_iam_policy_document.docker_runtime.json
}

data "aws_iam_policy_document" "vpn_runtime" {
  statement {
    sid       = "ServerPrivateKeyOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.vpn.arn]
  }
  statement {
    sid       = "DecryptThroughSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [module.encryption.key_arns.secrets]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.eu-west-1.amazonaws.com"]
    }
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = [for arn in var.ssm_artifact_bucket_arns : "${arn}/*"]
  }
}
resource "aws_iam_role_policy" "vpn_runtime" {
  name   = "${local.resource_prefix}-policy-vpn-runtime"
  role   = module.iam.role_names.vpn
  policy = data.aws_iam_policy_document.vpn_runtime.json
}
data "aws_iam_policy_document" "checkmk_artifacts" {
  statement {
    actions   = ["s3:GetObject"]
    resources = [for arn in var.ssm_artifact_bucket_arns : "${arn}/*"]
  }
}
resource "aws_iam_role_policy" "checkmk_artifacts" {
  name   = "${local.resource_prefix}-policy-checkmk-artifacts"
  role   = module.iam.role_names.checkmk
  policy = data.aws_iam_policy_document.checkmk_artifacts.json
}

data "aws_iam_policy_document" "backup_keys" {
  statement {
    sid       = "SourceAndVaultEncryption"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey"]
    resources = [module.encryption.key_arns.ebs, module.encryption.key_arns.efs, module.encryption.key_arns.backup]
  }
  statement {
    sid       = "ServiceResourceGrants"
    actions   = ["kms:CreateGrant"]
    resources = [module.encryption.key_arns.ebs, module.encryption.key_arns.efs, module.encryption.key_arns.backup]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}
resource "aws_iam_role_policy" "backup_keys" {
  name   = "${local.resource_prefix}-policy-backup-keys"
  role   = module.iam.role_names.backup
  policy = data.aws_iam_policy_document.backup_keys.json
}

# Export this for the existing recovery-role owner to review/attach; never mutate external role trust.
data "aws_iam_policy_document" "recovery_exports" {
  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [for prefix in values(module.storage.export_prefixes) : "${module.storage.bucket_arns.workload_exports}/${prefix}*"]
  }
  statement {
    actions   = ["s3:ListBucket", "s3:ListBucketVersions"]
    resources = [module.storage.bucket_arns.workload_exports]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for prefix in values(module.storage.export_prefixes) : "${prefix}*"]
    }
  }
  statement {
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [module.encryption.key_arns.exports]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.eu-west-1.amazonaws.com"]
    }
  }
}
