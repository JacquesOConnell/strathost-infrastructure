# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 6.1.
# ARCH: keep the nine diagram CIDRs across public, application and database tiers.

# DESIGN: public routing does not imply automatic public addresses on instances.
resource "aws_subnet" "public" {
  for_each = var.availability_zones

  vpc_id                          = aws_vpc.hosting.id
  availability_zone               = each.value
  cidr_block                      = local.subnet_cidrs[each.key].public
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-snet-public-${each.key}"
    Tier = "Public"
  })
}

resource "aws_subnet" "application" {
  for_each = var.availability_zones

  vpc_id                          = aws_vpc.hosting.id
  availability_zone               = each.value
  cidr_block                      = local.subnet_cidrs[each.key].application
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-snet-app-${each.key}"
    Tier = "Application"
  })
}

# Database subnets use only the isolated database route table; NACLs do not provide this isolation.
resource "aws_subnet" "database" {
  for_each = var.availability_zones

  vpc_id                          = aws_vpc.hosting.id
  availability_zone               = each.value
  cidr_block                      = local.subnet_cidrs[each.key].database
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-snet-db-${each.key}"
    Tier = "Database"
  })
}
