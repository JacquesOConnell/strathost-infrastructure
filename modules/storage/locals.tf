# Plan sections 4, 11 and 12: shared names, fixed EFS addresses and tags.
locals {
  resource_prefix = "strathost-${var.environment}-euw1"

  # The same privacy and ownership settings apply to these buckets.
  bucket_ids = merge({
    workload_exports = aws_s3_bucket.workload_exports.id
    alb_access_logs  = aws_s3_bucket.alb_access_logs.id
    }, var.enable_origin_trust ? {
    origin_trust = aws_s3_bucket.origin_trust[0].id
  } : {})

  efs_mount_addresses = { a = "10.0.4.20", b = "10.0.5.20", c = "10.0.6.20" }
  export_bucket_arn   = aws_s3_bucket.workload_exports.arn
  export_prefixes     = [for site in keys(var.site_posix_ids) : "sites/${site}/daily/"]

  tags = merge(var.additional_tags, {
    Project            = "StratHost"
    Application        = "WordPressHosting"
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Owner              = "Infrastructure"
    BusinessUnit       = "StratHost"
    Repository         = "strathost-infrastructure"
    CostCenter         = var.cost_center
    DataClassification = "Confidential"
    Criticality        = var.environment == "prod" ? "High" : "Standard"
    BackupPolicy       = "none"
  })
}
