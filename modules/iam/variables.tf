variable "environment" {
  description = "Deployment environment used in role names."
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Use dev, test or prod."
  }
}
variable "cost_center" {
  description = "Approved cost allocation label."
  type        = string
}
variable "additional_tags" {
  description = "Additional labels; mandatory labels take precedence."
  type        = map(string)
  default     = {}
}
