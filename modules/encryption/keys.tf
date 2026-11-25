# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 9.
# Separate service encryption boundaries and retain keys needed by stored data and recovery points.

locals {
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

# DESIGN: full service and recovery grants come from reviewed policies; a key for only the deployer is insufficient.

resource "aws_kms_key" "ebs" {
  description              = "StratHost ${var.environment}: EC2 volumes and source-encrypted snapshots"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["ebs"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-ebs"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "rds" {
  description              = "StratHost ${var.environment}: RDS storage and snapshots"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["rds"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-rds"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "efs" {
  description              = "StratHost ${var.environment}: Regional EFS WordPress uploads"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["efs"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-efs"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "backup" {
  description              = "StratHost ${var.environment}: AWS Backup recovery points"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["backup"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-backup"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "exports" {
  description              = "StratHost ${var.environment}: S3 application backup exports"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["exports"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-exports"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "secrets" {
  description              = "StratHost ${var.environment}: Application and service secrets"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["secrets"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-secrets"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "logs" {
  description              = "StratHost ${var.environment}: CloudWatch operational log groups"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  policy                   = var.key_policy_json["logs"]
  tags = merge(local.tags, {
    Name = "strathost-${var.environment}-euw1-kms-logs"
  })

  # Retained recovery points can still need these keys after compute is removed, including in test.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/strathost/${var.environment}/ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_alias" "rds" {
  name          = "alias/strathost/${var.environment}/rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_alias" "efs" {
  name          = "alias/strathost/${var.environment}/efs"
  target_key_id = aws_kms_key.efs.key_id
}

resource "aws_kms_alias" "backup" {
  name          = "alias/strathost/${var.environment}/backup"
  target_key_id = aws_kms_key.backup.key_id
}

resource "aws_kms_alias" "exports" {
  name          = "alias/strathost/${var.environment}/exports"
  target_key_id = aws_kms_key.exports.key_id
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/strathost/${var.environment}/secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_kms_alias" "logs" {
  name          = "alias/strathost/${var.environment}/logs"
  target_key_id = aws_kms_key.logs.key_id
}
