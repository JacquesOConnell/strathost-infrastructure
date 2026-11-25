variable "environment" { type = string }
variable "cost_center" { type = string }
variable "vpc_id" { type = string }
variable "private_zone_name" {
  type        = string
  description = "Approved private suffix, without a trailing dot."
}
variable "internal_hostname" {
  type        = string
  description = "Internal WordPress name within this private suffix."
  validation {
    condition     = var.internal_hostname == var.private_zone_name || endswith(var.internal_hostname, ".${var.private_zone_name}")
    error_message = "Internal hostname must belong to the selected private zone."
  }
}
variable "checkmk_hostname" {
  type        = string
  description = "Checkmk HTTPS hostname within the private suffix, matching its external certificate."
  validation {
    condition     = (var.checkmk_hostname == var.private_zone_name || endswith(var.checkmk_hostname, ".${var.private_zone_name}")) && var.checkmk_hostname != var.internal_hostname
    error_message = "Choose a distinct Checkmk hostname inside the private zone."
  }
}
variable "internal_alb_dns_name" { type = string }
variable "internal_alb_zone_id" { type = string }
variable "checkmk_private_ip" { type = string }
