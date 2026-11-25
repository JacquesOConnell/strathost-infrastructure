# Plan 6-8: preserve the diagram; pass role-scoped S3 policy rather than opening the endpoint.
module "networking" {
  source                  = "./modules/networking"
  environment             = var.environment
  cost_center             = var.cost_center
  availability_zones      = var.availability_zones
  single_nat_gateway      = var.single_nat_gateway
  s3_endpoint_policy_json = data.aws_iam_policy_document.s3_endpoint.json
}
module "security" {
  source                = "./modules/security"
  environment           = var.environment
  cost_center           = var.cost_center
  vpc_id                = module.networking.vpc_id
  cloudflare_enabled    = true
  cloudflare_ipv4_cidrs = jsondecode(file("${path.module}/config/cloudflare-ipv4.json")).ipv4_cidrs
  vpn_client_cidrs      = var.vpn_client_cidrs
}

# Endpoint policy is a limiting boundary; matching identity/bucket policies are still required.
data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    sid       = "ApprovedSSMArtifactReads"
    actions   = ["s3:GetObject"]
    resources = [for arn in var.ssm_artifact_bucket_arns : "${arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values   = [module.iam.role_arns.docker, module.iam.role_arns.vpn, module.iam.role_arns.checkmk]
    }
  }
  statement {
    sid       = "WriteApplicationExports"
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [for site in keys(local.site_posix_ids) : "arn:aws:s3:::${local.resource_prefix}-backup-${var.expected_account_id}/sites/${site}/daily/*"]
    principals {
      type        = "AWS"
      identifiers = [module.iam.role_arns.docker]
    }
  }
  statement {
    sid       = "ListApplicationExportPrefixes"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.resource_prefix}-backup-${var.expected_account_id}"]
    principals {
      type        = "AWS"
      identifiers = [module.iam.role_arns.docker, module.iam.role_arns.checkmk]
    }
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [for site in keys(local.site_posix_ids) : "sites/${site}/daily/*"]
    }
  }
  # Checkmk's S3 inventory/metrics collection uses bucket metadata, not object reads.
  statement {
    sid       = "MonitorOwnedBucketMetadata"
    actions   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation", "s3:GetBucketTagging"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [module.iam.role_arns.checkmk]
    }
  }
}
