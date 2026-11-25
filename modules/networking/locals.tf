# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 4, 6.1 and 7.1.
# Preserve stable subnet slots, address allocations and the selected NAT routing.

locals {
  resource_prefix = "strathost-${var.environment}-euw1"

  # ARCH / plan 6.1: these fixed ranges reproduce the diagram, not a calculated replacement layout.
  subnet_cidrs = {
    a = { public = "10.0.1.0/24", application = "10.0.4.0/24", database = "10.0.7.0/24" }
    b = { public = "10.0.2.0/24", application = "10.0.5.0/24", database = "10.0.8.0/24" }
    c = { public = "10.0.3.0/24", application = "10.0.6.0/24", database = "10.0.9.0/24" }
  }

  # ARCH / scope decision 3: one NAT in C is the baseline; per-AZ NAT is an optional recommendation.
  nat_zones = var.single_nat_gateway ? toset(["c"]) : toset(["a", "b", "c"])

  tags = merge(var.additional_tags, {
    Project            = "StratHost"
    Application        = "WordPressHosting"
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Owner              = "Infrastructure"
    BusinessUnit       = "StratHost"
    Repository         = "strathost-infrastructure"
    CostCenter         = var.cost_center
    DataClassification = "Internal"
    Criticality        = var.environment == "prod" ? "High" : "Standard"
    BackupPolicy       = "none"
  })
}
