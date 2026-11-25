# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 24.
# Provide identifiers and public trust-object metadata for IAM, hosts and load balancers.

output "bucket_names" {
  description = "Bucket names by purpose."
  value       = local.bucket_ids
}

output "bucket_arns" {
  description = "Bucket ARNs for least-privilege runtime and endpoint policy composition."
  value = merge({
    workload_exports = aws_s3_bucket.workload_exports.arn
    alb_access_logs  = aws_s3_bucket.alb_access_logs.arn
    }, var.enable_origin_trust ? {
    origin_trust = aws_s3_bucket.origin_trust[0].arn
  } : {})
}

output "export_prefixes" {
  description = "Site daily export prefixes; only one designated host schedules export jobs."
  value       = { for key in keys(var.site_posix_ids) : key => "sites/${key}/daily/" }
}

output "efs_file_system_id" {
  description = "Encrypted Regional EFS ID."
  value       = aws_efs_file_system.wordpress.id
}

output "efs_file_system_arn" {
  description = "Filesystem ARN for scoped IAM policies."
  value       = aws_efs_file_system.wordpress.arn
}

output "efs_access_points" {
  description = "Stable per-site access-point IDs, ARNs and POSIX IDs for host configuration."
  value = {
    for key, access_point in aws_efs_access_point.site : key => {
      id       = access_point.id
      arn      = access_point.arn
      posix_id = var.site_posix_ids[key]
    }
  }
}

output "origin_ca_object" {
  description = "Versioned public CA object for the ALB trust store; null when origin trust is disabled."
  value = var.enable_origin_trust ? {
    bucket     = aws_s3_object.origin_ca_bundle[0].bucket
    key        = aws_s3_object.origin_ca_bundle[0].key
    version_id = aws_s3_object.origin_ca_bundle[0].version_id
  } : null
}
