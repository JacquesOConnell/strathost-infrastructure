# Plan section 24: expose the connection metadata, never the administrator password.
output "database_endpoint" {
  description = "RDS DNS address for site configuration."
  value       = aws_db_instance.wordpress.address
}

output "database_port" {
  description = "MySQL connection port."
  value       = aws_db_instance.wordpress.port
}

output "database_identifier" {
  description = "Identifier used by Checkmk's AWS integration."
  value       = aws_db_instance.wordpress.identifier
}

output "database_arn" {
  description = "RDS resource ARN for scoped administration and monitoring."
  value       = aws_db_instance.wordpress.arn
}

output "administrator_secret_arn" {
  description = "RDS-managed secret ARN for the separately authorised database-initialisation workflow."
  value       = aws_db_instance.wordpress.master_user_secret[0].secret_arn
}
