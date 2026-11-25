# Plan section 14: ordinary inputs, with no credentials or generated AMI selection.
variable "environment" {
  description = "Deployment profile used for names and initial sizing."
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

variable "public_subnet_ids" {
  description = "Public subnet IDs keyed a, b and c."
  type        = map(string)
  validation {
    condition     = toset(keys(var.public_subnet_ids)) == toset(["a", "b", "c"])
    error_message = "Provide the three subnet slots a, b and c."
  }
}

variable "application_subnet_ids" {
  description = "Private application subnet IDs keyed a, b and c."
  type        = map(string)
  validation {
    condition     = toset(keys(var.application_subnet_ids)) == toset(["a", "b", "c"])
    error_message = "Provide the three subnet slots a, b and c."
  }
}

variable "docker_ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 AMD64 AMI for the Docker hosts."
  type        = string
}

variable "vpn_ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 AMD64 AMI for VPN."
  type        = string
}

variable "checkmk_ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 AMD64 AMI for Checkmk."
  type        = string
}

variable "docker_security_group_id" {
  description = "Dedicated Docker security group."
  type        = string
}

variable "vpn_security_group_id" {
  description = "Dedicated WireGuard security group."
  type        = string
}

variable "checkmk_security_group_id" {
  description = "Dedicated Checkmk security group."
  type        = string
}

variable "docker_instance_profile_name" {
  description = "Docker instance profile from IAM."
  type        = string
}

variable "vpn_instance_profile_name" {
  description = "VPN instance profile from IAM."
  type        = string
}

variable "checkmk_instance_profile_name" {
  description = "Checkmk instance profile from IAM."
  type        = string
}

variable "ebs_kms_key_arn" {
  description = "Key used to encrypt root and Checkmk data volumes."
  type        = string
}

variable "bootstrap_user_data" {
  description = "Versioned non-secret bootstrap that establishes SSM; service setup follows attachment completion."
  type        = string
}

variable "protect_instances" {
  description = "Enable API termination protection; disable only for an approved change."
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional labels; mandatory labels take precedence."
  type        = map(string)
  default     = {}
}
