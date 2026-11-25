variable "environment" {
  description = "Environment used to scope the StratHost resources."
  type        = string
}

variable "expected_account_id" {
  description = "Approved AWS account for the monitoring policy."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Provide the twelve-digit account ID."
  }
}

variable "checkmk_role_name" {
  description = "Existing Checkmk instance role name from IAM; not a user access key."
  type        = string
}

variable "private_ip_addresses" {
  description = "Five server addresses from EC2, keyed docker_01, docker_02, docker_03, vpn and checkmk."
  type        = map(string)
}
variable "vpc_id" {
  type        = string
  description = "Dedicated VPC whose flow records are retained for traffic troubleshooting."
}
variable "logs_kms_key_arn" {
  type        = string
  description = "Key authorized for the exact VPC diagnostic log group."
}
variable "cost_center" {
  type        = string
  description = "Approved cost allocation label."
}
