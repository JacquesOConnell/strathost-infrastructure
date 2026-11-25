# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 9 and 23.
# Require reviewed per-purpose policies instead of a permissive default key policy.

variable "environment" {
  description = "Deployment profile."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
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

variable "key_policy_json" {
  description = "Complete reviewed policies for seven purposes, including recovery, administration and the required service/role permissions."
  type        = map(string)
  validation {
    condition = (
      toset(keys(var.key_policy_json)) == toset(["ebs", "rds", "efs", "backup", "exports", "secrets", "logs"]) &&
      alltrue([for policy in values(var.key_policy_json) : try(
        jsondecode(policy).Version == "2012-10-17" && length(tolist(jsondecode(policy).Statement)) > 0,
        false
      )])
    )
    error_message = "Supply non-empty IAM JSON policies for ebs, rds, efs, backup, exports, secrets and logs."
  }
}

variable "additional_tags" {
  description = "Additional labels; mandatory labels take precedence."
  type        = map(string)
  default     = {}
}
