# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5 and 23.1.
# Keep account identities and backend paths explicit; these are deployment inputs, not inferred lab values.

variable "expected_account_id" {
  description = "Owner-approved AWS account for state bootstrap; never infer from the Checkmk lab."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply the twelve-digit account explicitly."
  }
}

variable "aws_region" {
  description = "Architecture region. A different region requires revising the release baseline."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.aws_region == "eu-west-1"
    error_message = "The implemented baseline targets eu-west-1."
  }
}

variable "cost_center" {
  description = "Owner-approved cost allocation label."
  type        = string

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "A non-empty cost center is required."
  }
}

variable "key_administrator_role_arns" {
  description = "Existing same-account IAM roles authorised to administer the state encryption key."
  type        = set(string)

  validation {
    condition = length(var.key_administrator_role_arns) > 0 && alltrue([
      for arn in var.key_administrator_role_arns :
      can(regex("^arn:aws:iam::${var.expected_account_id}:role/[A-Za-z0-9+=,.@_/-]+$", arn))
    ])
    error_message = "Provide at least one existing IAM role ARN in the approved account, not an STS session ARN."
  }
}

variable "backend_access" {
  description = "Existing roles and their exact backend keys; bootstrap migration is a separate explicit entry. Policies are emitted for attachment by the identity owner."
  type = map(object({
    role_arn   = string
    state_keys = set(string)
  }))

  validation {
    condition = length(var.backend_access) > 0 && alltrue([
      for name, access in var.backend_access :
      can(regex("^[a-z][a-z0-9_-]{0,31}$", name)) &&
      can(regex("^arn:aws:iam::${var.expected_account_id}:role/[A-Za-z0-9+=,.@_/-]+$", access.role_arn)) &&
      length(access.state_keys) > 0 && alltrue([
        for key in access.state_keys :
        contains([
          "bootstrap/terraform.tfstate",
          "environments/dev/terraform.tfstate",
          "environments/test/terraform.tfstate",
          "environments/prod/terraform.tfstate",
          "dns/dev/terraform.tfstate",
          "dns/test/terraform.tfstate",
          "dns/prod/terraform.tfstate"
        ], key)
      ])
    ])
    error_message = "Each named backend entry requires a same-account role and exact approved state keys; no wildcards or workspaces."
  }
}

variable "additional_tags" {
  description = "Additional non-secret labels; mandatory governance labels cannot be overridden."
  type        = map(string)
  default     = {}
}
