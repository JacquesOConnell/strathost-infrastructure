# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 8 and 23.1.
# Require approved origin and VPN sources rather than silently opening ingress.

variable "environment" {
  description = "Deployment profile."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}

variable "vpc_id" {
  description = "Dedicated VPC from networking."
  type        = string
}

variable "cost_center" {
  description = "Approved cost allocation label."
  type        = string

  validation {
    condition     = length(trimspace(var.cost_center)) > 0
    error_message = "Cost center is required."
  }
}

variable "cloudflare_enabled" {
  description = "Require reviewed Cloudflare origin CIDRs; mandatory in production."
  type        = bool
  default     = false

  validation {
    condition     = var.environment != "prod" || var.cloudflare_enabled
    error_message = "Production requires the Cloudflare origin restriction."
  }
}

variable "cloudflare_ipv4_cidrs" {
  description = "Reviewed, versioned Cloudflare IPv4 origin ranges; no live HTTP lookup during plan."
  type        = set(string)
  default     = []

  validation {
    condition = (
      (!var.cloudflare_enabled || length(var.cloudflare_ipv4_cidrs) > 0) &&
      alltrue([for cidr in var.cloudflare_ipv4_cidrs :
        can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
      ])
    )
    error_message = "Enabled Cloudflare requires non-empty IPv4 CIDRs; world-open ranges are prohibited."
  }
}

variable "origin_test_cidrs" {
  description = "Approved IPv4 clients for restricted non-production origin tests when Cloudflare is disabled."
  type        = set(string)
  default     = []

  validation {
    condition = (
      (var.cloudflare_enabled || length(var.origin_test_cidrs) > 0) &&
      alltrue([for cidr in var.origin_test_cidrs :
        can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
      ])
    )
    error_message = "Provide explicit non-world-open IPv4 origin-test ranges when Cloudflare is disabled."
  }
}

variable "vpn_client_cidrs" {
  description = "Approved public client ranges for WireGuard UDP 51820."
  type        = set(string)

  validation {
    condition = length(var.vpn_client_cidrs) > 0 && alltrue([
      for cidr in var.vpn_client_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "WireGuard requires explicit IPv4 client CIDRs; 0.0.0.0/0 is not permitted."
  }
}

variable "additional_tags" {
  description = "Additional labels; mandatory labels take precedence."
  type        = map(string)
  default     = {}
}
