variable "environment" {
  type        = string
  description = "Environment used in Access application and policy names."
}
variable "account_id" {
  type        = string
  description = "Approved existing Cloudflare account ID."
}
variable "zone_id" {
  type        = string
  description = "Approved existing Cloudflare zone ID."
}
variable "public_hostname" {
  type        = string
  description = "Public site's exact FQDN."
}
variable "secure_hostname" {
  type        = string
  description = "Secure site's exact distinct FQDN."
  validation {
    condition     = var.secure_hostname != var.public_hostname
    error_message = "Public and secure hostnames must differ."
  }
}
variable "public_origin_dns" {
  type        = string
  description = "Public ALB DNS name, not an IP address."
}
variable "secure_origin_dns" {
  type        = string
  description = "Secure ALB DNS name."
}
variable "approved_identity_provider_id" {
  type        = string
  description = "One approved existing IdP with MFA enforced upstream."
}
variable "approved_emails" {
  type        = set(string)
  description = "Explicit owner-approved Access user emails; never Everyone or a broad domain allowlist."
  validation {
    condition = length(var.approved_emails) > 0 && alltrue([
      for email in var.approved_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", email))
    ])
    error_message = "Supply a non-empty explicit approved email allowlist."
  }
}
variable "publish_dns" {
  type        = bool
  description = "Enable after origin health, certificate, Access and bypass tests."
  default     = false
  validation {
    condition     = !var.publish_dns || var.origin_tests_verified && var.zone_settings_verified
    error_message = "Do not publish before recording origin tests and strict edge TLS settings."
  }
}
variable "origin_tests_verified" {
  type        = bool
  description = "Operator attestation of recorded origin authentication tests."
  default     = false
}
variable "zone_settings_verified" {
  type        = bool
  description = "Operator attestation of Full (strict), TLS 1.2 minimum and edge HTTPS redirect."
  default     = false
}
variable "manage_zone_settings" {
  type        = bool
  description = "Explicitly own shared zone-wide TLS settings only after impact review."
  default     = false
}
