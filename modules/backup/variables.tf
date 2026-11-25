variable "environment" {
  type        = string
  description = "Environment used in backup names and retention."
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "cost_center" {
  type        = string
  description = "Approved cost allocation label."
}
variable "backup_kms_key_arn" {
  type        = string
  description = "Vault encryption key. EC2/EBS snapshots still depend on source encryption keys."
}
variable "backup_role_arn" {
  type        = string
  description = "Dedicated AWS Backup service role with backup and source-key permissions."
}
variable "instance_arns" {
  type        = list(string)
  description = "Exactly the five supplied EC2 servers, including Checkmk with its attached data disk."
  validation {
    condition     = length(distinct(var.instance_arns)) == 5
    error_message = "Select the five distinct EC2 servers explicitly."
  }
}
variable "efs_file_system_arn" {
  type        = string
  description = "The shared Regional EFS filesystem."
}
variable "additional_tags" {
  type        = map(string)
  description = "Additional labels; mandatory labels take precedence."
  default     = {}
}
