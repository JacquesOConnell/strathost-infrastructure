variable "environment" {
  description = "Deployment environment used in names and the sizing profile."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}

variable "cost_center" {
  description = "Cost allocation label."
  type        = string
}

variable "database_subnet_ids" {
  description = "The three isolated database subnet IDs from networking."
  type        = list(string)
  validation {
    condition     = length(distinct(var.database_subnet_ids)) == 3
    error_message = "Supply the three distinct database subnets."
  }
}

variable "mysql_security_group_id" {
  description = "The dedicated MySQL security group from security."
  type        = string
}

variable "rds_kms_key_arn" {
  description = "Key for encrypted database storage and snapshots."
  type        = string
}

variable "secrets_kms_key_arn" {
  description = "Key for the RDS-managed administrator secret."
  type        = string
}

variable "logs_kms_key_arn" {
  description = "Key for database diagnostic logs, not a separate alerting system."
  type        = string
}

variable "engine_version" {
  description = "Reviewed MySQL 8.4 patch; confirm regional availability before deployment."
  type        = string
  default     = "8.4.13"
}

variable "final_snapshot_suffix" {
  description = "Unique approved release label for the final snapshot; do not use a changing timestamp expression."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.final_snapshot_suffix)) && length(var.final_snapshot_suffix) <= 40
    error_message = "Use a short lowercase release label containing letters, digits and single hyphens."
  }
}

variable "skip_final_snapshot" {
  description = "Allow omission only for explicitly disposable non-production data."
  type        = bool
  default     = false
  validation {
    condition     = var.environment != "prod" || !var.skip_final_snapshot
    error_message = "Production must retain the final database snapshot."
  }
}

variable "deletion_protection" {
  description = "Disable only during an approved replacement or teardown."
  type        = bool
  default     = true
}

variable "monitoring_role_arn" {
  description = "Optional Enhanced Monitoring role; Checkmk AWS metrics do not require it."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Additional labels; required labels take precedence."
  type        = map(string)
  default     = {}
}
