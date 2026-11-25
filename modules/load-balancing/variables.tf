variable "environment" {
  type        = string
  description = "Environment for names and deletion protection."
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "cost_center" {
  type        = string
  description = "Approved cost allocation label."
}
variable "vpc_id" {
  type        = string
  description = "Dedicated VPC for the instance target groups."
}
variable "public_subnet_ids" {
  type        = map(string)
  description = "The public a/b/c subnet IDs."
  validation {
    condition     = toset(keys(var.public_subnet_ids)) == toset(["a", "b", "c"])
    error_message = "Supply public subnet slots a/b/c."
  }
}
variable "application_subnet_ids" {
  type        = map(string)
  description = "The application a/b/c subnet IDs for the internal ALB."
  validation {
    condition     = toset(keys(var.application_subnet_ids)) == toset(["a", "b", "c"])
    error_message = "Supply application subnet slots a/b/c."
  }
}
variable "public_alb_security_group_id" {
  type        = string
  description = "Dedicated public ALB security group."
}
variable "secure_alb_security_group_id" {
  type        = string
  description = "Dedicated secure ALB security group."
}
variable "internal_alb_security_group_id" {
  type        = string
  description = "Dedicated internal ALB security group."
}
variable "docker_instance_ids" {
  type        = map(string)
  description = "The three Docker instance IDs with stable keys."
  validation {
    condition     = toset(keys(var.docker_instance_ids)) == toset(["docker_01", "docker_02", "docker_03"])
    error_message = "Register exactly the supplied three Docker hosts."
  }
}
variable "access_logs_bucket_name" {
  type        = string
  description = "Private SSE-S3 bucket with ALB delivery policy already configured."
}
variable "certificate_arns" {
  type        = map(string)
  description = "Existing issued regional ACM certificates keyed public/secure/internal. Never private keys."
  validation {
    condition = toset(keys(var.certificate_arns)) == toset(["public", "secure", "internal"]) && alltrue([
      for arn in values(var.certificate_arns) : can(regex("^arn:aws:acm:eu-west-1:[0-9]{12}:certificate/", arn))
    ])
    error_message = "Provide eu-west-1 ACM certificate ARNs for all three listeners."
  }
}
variable "hostnames" {
  type        = map(string)
  description = "Three distinct approved FQDNs keyed public/secure/internal."
  validation {
    condition = toset(keys(var.hostnames)) == toset(["public", "secure", "internal"]) && length(distinct(values(var.hostnames))) == 3 && alltrue([
      for hostname in values(var.hostnames) : can(regex("^[a-z0-9][a-z0-9.-]+\\.[a-z]{2,}$", hostname))
    ])
    error_message = "Provide three distinct lowercase FQDNs without wildcards."
  }
}
variable "enable_public_routing" {
  type        = bool
  description = "Enable only after origin and application health tests."
  default     = false
}
variable "enable_internal_routing" {
  type        = bool
  description = "Enable after private VPN/DNS and application authorization tests."
  default     = false
}
variable "enable_secure_routing" {
  type        = bool
  description = "Enable after Cloudflare Access and origin token validation tests."
  default     = false
  validation {
    condition     = !var.enable_secure_routing || var.secure_origin_auth_verified
    error_message = "Do not enable secure routing before verifying origin JWT authentication."
  }
}
variable "secure_origin_auth_verified" {
  type        = bool
  description = "Operator attestation of recorded authentication/bypass tests, not an authentication mechanism."
  default     = false
}
variable "additional_tags" {
  type        = map(string)
  description = "Additional labels; mandatory labels take precedence."
  default     = {}
}
