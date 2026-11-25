# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 11, 12 and 23.2.
# Keep key ownership, runtime/recovery identities and site allocations explicit.

variable "environment" {
  description = "Deployment profile."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}

variable "expected_account_id" {
  description = "Approved workload account, used in names and principal validation."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply the twelve-digit workload account ID."
  }
}

variable "cost_center" {
  description = "Approved cost allocation label."
  type        = string
  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "Cost center is required."
  }
}

variable "efs_kms_key_arn" {
  description = "KMS key ARN used to encrypt EFS."
  type        = string
}

variable "exports_kms_key_arn" {
  description = "KMS key ARN used to encrypt application exports."
  type        = string
}

variable "application_subnet_ids" {
  description = "Private application subnet IDs from networking, keyed a/b/c."
  type        = map(string)
  validation {
    condition     = toset(keys(var.application_subnet_ids)) == toset(["a", "b", "c"])
    error_message = "Supply exactly the three application subnet slots a, b and c."
  }
}

variable "efs_security_group_id" {
  description = "Dedicated wordpress_efs security group."
  type        = string
}

variable "docker_runtime_role_arn" {
  description = "Shared Docker runtime role: EFS client access and write-only backup exports."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::${var.expected_account_id}:role/[A-Za-z0-9+=,.@_/-]+$", var.docker_runtime_role_arn))
    error_message = "Supply the same-account Docker IAM role ARN."
  }
}

variable "recovery_role_arn" {
  description = "Approved same-account role allowed to read and recover application exports."
  type        = string
  validation {
    condition = (
      can(regex("^arn:aws:iam::${var.expected_account_id}:role/[A-Za-z0-9+=,.@_/-]+$", var.recovery_role_arn)) &&
      var.recovery_role_arn != var.docker_runtime_role_arn
    )
    error_message = "Recovery must use a distinct same-account IAM role."
  }
}

variable "site_posix_ids" {
  description = "Site keys and their stable UID/GID; each site needs a distinct integer ID."
  type        = map(number)
  default = {
    public_wordpress   = 10001
    secure_wordpress   = 10002
    internal_wordpress = 10003
  }
  validation {
    condition = (
      length(var.site_posix_ids) > 0 &&
      length(distinct(values(var.site_posix_ids))) == length(var.site_posix_ids) &&
      alltrue([for name, id in var.site_posix_ids :
        can(regex("^[a-z][a-z0-9_]{0,39}$", name)) && id >= 10000 && id <= 60000 && id == floor(id)
      ])
    )
    error_message = "Use safe site names and distinct integer POSIX IDs from 10000 to 60000."
  }
}

variable "enable_origin_trust" {
  description = "Optional custom origin mTLS trust-artifact bucket; excluded from the diagram baseline."
  type        = bool
  default     = false
}

variable "origin_ca_bundle_file" {
  description = "Reviewed public PEM CA bundle file. Never provide a private key."
  type        = string
  default     = null
  validation {
    condition = !var.enable_origin_trust || try(
      strcontains(file(var.origin_ca_bundle_file), "-----BEGIN CERTIFICATE-----") &&
      !strcontains(file(var.origin_ca_bundle_file), "PRIVATE KEY"),
      false
    )
    error_message = "Enabled origin trust requires a readable public certificate PEM file without private-key content."
  }
}

variable "additional_tags" {
  description = "Additional labels; mandatory labels take precedence."
  type        = map(string)
  default     = {}
}
