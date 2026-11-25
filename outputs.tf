output "account_id" {
  description = "Verified provider account, not the separate lab account."
  value       = data.aws_caller_identity.current.account_id
}
output "vpc_id" { value = module.networking.vpc_id }
output "availability_zone_ids" { value = module.networking.availability_zone_ids }
output "docker_instance_ids" { value = module.ec2.docker_instance_ids }
output "vpn_instance_id" { value = module.ec2.vpn_instance_id }
output "vpn_public_ip" { value = module.ec2.vpn_public_ip }
output "checkmk_instance_id" { value = module.ec2.checkmk_instance_id }
output "checkmk_data_volume_id" { value = module.ec2.checkmk_data_volume_id }
output "private_ip_addresses" { value = module.ec2.private_ip_addresses }
output "database_address" { value = module.database.database_endpoint }
output "database_admin_secret_arn" { value = module.database.administrator_secret_arn }
output "site_secret_arns" {
  description = "Empty containers until the approved secret provisioning stage. No values are output."
  value       = { for site, secret in aws_secretsmanager_secret.wordpress : site => secret.arn }
}
output "vpn_secret_arn" { value = aws_secretsmanager_secret.vpn.arn }
output "efs_file_system_id" { value = module.storage.efs_file_system_id }
output "efs_access_points" { value = module.storage.efs_access_points }
output "bucket_names" { value = module.storage.bucket_names }
output "alb_dns_names" { value = module.load_balancing.dns_names }
output "target_group_arns" { value = module.load_balancing.target_group_arns }
output "monitoring_inventory" { value = module.monitoring.host_inventory }
output "backup_vault_name" { value = module.backup.vault_name }
output "recovery_export_policy_json" {
  description = "Proposed export-read policy for the existing recovery-role owner; does not include EC2/EFS/RDS restore authority."
  value       = data.aws_iam_policy_document.recovery_exports.json
}
