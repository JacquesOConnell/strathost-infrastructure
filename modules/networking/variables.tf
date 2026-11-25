# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 6.1, 7.1 and 23.1.
# Expose the required network choices without turning the fixed diagram into a generic VPC generator.

variable "environment" {
  description = "Deployment profile: dev, test or prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test or prod."
  }
}

variable "availability_zones" {
  description = "Three approved AZ names, keyed a, b and c."
  type        = map(string)
  validation {
    condition = (
      toset(keys(var.availability_zones)) == toset(["a", "b", "c"]) &&
      length(distinct(values(var.availability_zones))) == 3
    )
    error_message = "Provide three distinct AZ names under a, b and c."
  }
}

variable "single_nat_gateway" {
  description = "Diagram baseline: one NAT in C; set false for the optional per-AZ design."
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Approved cost allocation label."
  type        = string

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "Cost center must not be empty."
  }
}

variable "s3_endpoint_policy_json" {
  description = "Reviewed endpoint policy supplied by the environment root: regional bootstrap reads and role-scoped exports only. Never pass an unrestricted default policy."
  type        = string

  validation {
    condition = try(
      jsondecode(var.s3_endpoint_policy_json).Version == "2012-10-17" &&
      length(tolist(jsondecode(var.s3_endpoint_policy_json).Statement)) > 0,
      false
    )
    error_message = "Supply a valid, non-empty IAM JSON policy with version 2012-10-17."
  }
}

variable "additional_tags" {
  description = "Additional labels; mandatory governance and resource-name tags take precedence."
  type        = map(string)
  default     = {}
}
