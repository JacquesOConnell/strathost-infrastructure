variable "environment" {
  description = "Approved isolated environment. Backend key must match this selection."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "expected_account_id" {
  description = "Approved StratHost workload account; no default account is selected."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply the approved twelve-digit account ID."
  }
}
variable "cost_center" {
  description = "Approved cost allocation label."
  type        = string
}
variable "availability_zones" {
  description = "Reviewed account-specific eu-west-1 AZ names, keyed a/b/c."
  type        = map(string)
}
variable "docker_ami_id" {
  description = "Pinned Canonical Ubuntu 24.04 AMD64 AMI for Docker."
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
variable "key_administrator_role_arns" {
  description = "Existing approved same-account key administration roles. Include the applying role to preserve manageability."
  type        = set(string)
  validation {
    condition = length(var.key_administrator_role_arns) > 0 && alltrue([
      for arn in var.key_administrator_role_arns : can(regex("^arn:aws:iam::${var.expected_account_id}:role/", arn))
    ])
    error_message = "Supply at least one approved same-account role ARN."
  }
}
variable "recovery_role_arn" {
  description = "Existing approved distinct recovery role with restore authority; no trust/attachments are changed on that role."
  type        = string
}
variable "vpn_client_cidrs" {
  description = "Approved public IPv4 source ranges for UDP 51820; no world-open input."
  type        = set(string)
}
variable "certificate_arns" {
  description = "Existing issued ACM certificate ARNs keyed public/secure/internal, eu-west-1."
  type        = map(string)
}
variable "hostnames" {
  description = "Approved distinct FQDNs keyed public/secure/internal."
  type        = map(string)
}
variable "private_dns_zone_name" {
  description = "Approved private DNS suffix containing internal WordPress and Checkmk names."
  type        = string
}
variable "checkmk_hostname" {
  description = "Private Checkmk name matching its separately provisioned trusted HTTPS certificate."
  type        = string
}
variable "final_snapshot_suffix" {
  description = "Stable unique release label for the eventual RDS final snapshot."
  type        = string
}
variable "ssm_artifact_bucket_arns" {
  description = "Reviewed eu-west-1 AWS-owned SSM/patch artifact bucket ARNs required by the selected operations; bucket ARNs without /*."
  type        = set(string)
  validation {
    condition = length(var.ssm_artifact_bucket_arns) > 0 && alltrue([
      for arn in var.ssm_artifact_bucket_arns : can(regex("^arn:aws:s3:::[a-z0-9.-]+$", arn))
    ])
    error_message = "Provide reviewed regional SSM artifact bucket ARNs."
  }
}
variable "single_nat_gateway" {
  description = "Diagram baseline: one NAT in C. False selects the separate per-AZ recommendation."
  type        = bool
  default     = true
}
variable "enable_public_routing" {
  description = "Publish only after application and origin checks."
  type        = bool
  default     = false
}
variable "enable_internal_routing" {
  description = "Enable only after VPN/private DNS and application authorization checks."
  type        = bool
  default     = false
}
variable "enable_secure_routing" {
  description = "Publish only after Access and origin JWT/bypass checks."
  type        = bool
  default     = false
}
variable "secure_origin_auth_verified" {
  description = "Attestation of recorded secure-origin authentication tests; does not provide authentication itself."
  type        = bool
  default     = false
}
