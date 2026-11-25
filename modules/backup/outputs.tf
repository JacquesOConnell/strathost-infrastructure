output "vault_name" {
  description = "Vault used by monitoring and recovery runbooks."
  value       = aws_backup_vault.workloads.name
}
output "vault_arn" {
  value = aws_backup_vault.workloads.arn
}
output "plan_id" {
  value = aws_backup_plan.workloads.id
}
output "selected_resource_arns" {
  description = "Explicit selection is not proof of completed or recoverable backups."
  value       = aws_backup_selection.workloads.resources
}
