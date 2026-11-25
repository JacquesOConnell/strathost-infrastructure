# Plan 11-13: one Regional EFS, site access points and separate export/log buckets.
module "storage" {
  source                  = "./modules/storage"
  environment             = var.environment
  expected_account_id     = var.expected_account_id
  cost_center             = var.cost_center
  efs_kms_key_arn         = module.encryption.key_arns.efs
  exports_kms_key_arn     = module.encryption.key_arns.exports
  application_subnet_ids  = module.networking.application_subnet_ids
  efs_security_group_id   = module.security.security_group_ids.wordpress_efs
  docker_runtime_role_arn = module.iam.role_arns.docker
  recovery_role_arn       = var.recovery_role_arn
  site_posix_ids          = local.site_posix_ids
}
module "database" {
  source                  = "./modules/database"
  environment             = var.environment
  cost_center             = var.cost_center
  database_subnet_ids     = values(module.networking.database_subnet_ids)
  mysql_security_group_id = module.security.security_group_ids.mysql
  rds_kms_key_arn         = module.encryption.key_arns.rds
  secrets_kms_key_arn     = module.encryption.key_arns.secrets
  logs_kms_key_arn        = module.encryption.key_arns.logs
  final_snapshot_suffix   = var.final_snapshot_suffix
}
