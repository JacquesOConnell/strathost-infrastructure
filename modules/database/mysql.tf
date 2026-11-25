# Plan section 13 / diagram A09: one RDS deployment manages both primary and standby.
resource "aws_db_subnet_group" "wordpress" {
  name        = "${local.resource_prefix}-dbsubnet-mysql"
  description = "StratHost isolated database subnets"
  subnet_ids  = var.database_subnet_ids
  tags        = merge(local.tags, { Name = "${local.resource_prefix}-dbsubnet-mysql" })
}

resource "aws_db_parameter_group" "wordpress" {
  name   = "${local.resource_prefix}-mysql84"
  family = "mysql8.4"
  tags   = merge(local.tags, { Name = "${local.resource_prefix}-mysql84" })

  # Require encrypted application connections; clients must also verify the RDS certificate.
  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
  parameter {
    name  = "collation_server"
    value = "utf8mb4_0900_ai_ci"
  }
  parameter {
    name  = "slow_query_log"
    value = "1"
  }
  parameter {
    name  = "long_query_time"
    value = "2"
  }
  parameter {
    name  = "log_output"
    value = "FILE"
  }
  parameter {
    name  = "general_log"
    value = "0"
  }
}

# These groups hold diagnostic logs; monitoring and notifications belong to Checkmk.
resource "aws_cloudwatch_log_group" "mysql_error" {
  name              = "/aws/rds/instance/${local.db_identifier}/error"
  retention_in_days = var.environment == "prod" ? 90 : 14
  kms_key_id        = var.logs_kms_key_arn
  tags              = merge(local.tags, { Name = "${local.resource_prefix}-logs-mysql-error" })
}

resource "aws_cloudwatch_log_group" "mysql_slowquery" {
  name              = "/aws/rds/instance/${local.db_identifier}/slowquery"
  retention_in_days = var.environment == "prod" ? 90 : 14
  kms_key_id        = var.logs_kms_key_arn
  tags              = merge(local.tags, { Name = "${local.resource_prefix}-logs-mysql-slowquery" })
}

resource "aws_db_instance" "wordpress" {
  identifier     = local.db_identifier
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.environment == "prod" ? "db.t4g.medium" : "db.t4g.micro"

  # The supplied primary/standby design remains Multi-AZ in every environment.
  # AWS selects the standby AZ; this is not a read replica or a second Terraform DB resource.
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [var.mysql_security_group_id]
  publicly_accessible    = false
  network_type           = "IPV4"
  port                   = 3306

  storage_type          = "gp3"
  allocated_storage     = var.environment == "prod" ? 100 : 20
  max_allocated_storage = var.environment == "prod" ? 500 : 100
  storage_encrypted     = true
  kms_key_id            = var.rds_kms_key_arn

  # RDS generates and rotates the admin password. Terraform stores only the secret ARN.
  db_name                             = "strathost"
  username                            = "strathost_admin"
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.secrets_kms_key_arn
  iam_database_authentication_enabled = false
  parameter_group_name                = aws_db_parameter_group.wordpress.name
  ca_cert_identifier                  = "rds-ca-rsa2048-g1"

  backup_retention_period   = var.environment == "prod" ? 14 : 1
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.resource_prefix}-mysql-final-${var.final_snapshot_suffix}"

  auto_minor_version_upgrade      = false
  allow_major_version_upgrade     = false
  apply_immediately               = false
  engine_lifecycle_support        = "open-source-rds-extended-support-disabled"
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  database_insights_mode                = "standard"
  performance_insights_enabled          = var.environment == "prod"
  performance_insights_retention_period = var.environment == "prod" ? 7 : null
  performance_insights_kms_key_id       = var.environment == "prod" ? var.rds_kms_key_arn : null
  monitoring_interval                   = var.monitoring_role_arn == null ? 0 : 60
  monitoring_role_arn                   = var.monitoring_role_arn

  tags       = merge(local.tags, { Name = local.db_identifier })
  depends_on = [aws_cloudwatch_log_group.mysql_error, aws_cloudwatch_log_group.mysql_slowquery]
}
