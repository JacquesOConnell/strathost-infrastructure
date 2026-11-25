# Plan 18/19: Checkmk owns monitoring; AWS Backup owns recovery-point creation.
module "monitoring" {
  source               = "./modules/monitoring"
  environment          = var.environment
  expected_account_id  = var.expected_account_id
  checkmk_role_name    = module.iam.role_names.checkmk
  private_ip_addresses = module.ec2.private_ip_addresses
  vpc_id               = module.networking.vpc_id
  logs_kms_key_arn     = module.encryption.key_arns.logs
  cost_center          = var.cost_center
}
module "backup" {
  source             = "./modules/backup"
  environment        = var.environment
  cost_center        = var.cost_center
  backup_kms_key_arn = module.encryption.key_arns.backup
  backup_role_arn    = module.iam.role_arns.backup
  instance_arns = [for id in concat(values(module.ec2.docker_instance_ids), [module.ec2.vpn_instance_id, module.ec2.checkmk_instance_id]) :
    "arn:aws:ec2:eu-west-1:${var.expected_account_id}:instance/${id}"
  ]
  efs_file_system_arn = module.storage.efs_file_system_arn
  depends_on          = [aws_iam_role_policy.backup_keys, module.ec2]
}
