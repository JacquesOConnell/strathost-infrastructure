# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 6.1; traceability A01-A03.
# Preserve the diagram VPC and check that the selected AZ names are available in this account.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

resource "aws_vpc" "hosting" {
  cidr_block                       = "10.0.0.0/16"
  instance_tenancy                 = "default"
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = false
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-vpc"
  })

  lifecycle {
    precondition {
      condition = alltrue([
        for zone in values(var.availability_zones) :
        contains(data.aws_availability_zones.available.names, zone)
      ])
      error_message = "Each AZ must be an available standard zone in the provider account and region."
    }
  }
}

# MASTER / trace A03: the gateway belongs to the VPC, even though the diagram draws it in AZ B.
resource "aws_internet_gateway" "hosting" {
  vpc_id = aws_vpc.hosting.id
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-igw"
  })
}
