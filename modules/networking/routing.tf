# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 7.1; traceability A03.
# Separate internet-facing, outbound-only application and isolated database routing.

resource "aws_eip" "nat" {
  for_each = local.nat_zones

  domain = "vpc"
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-eip-nat-${each.key}"
  })
}

# MASTER: these are zonal public NAT gateways; the IGW and subnet ACL must exist first.
resource "aws_nat_gateway" "application_egress" {
  for_each = local.nat_zones

  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.public[each.key].id
  connectivity_type = "public"
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.hosting, aws_default_network_acl.hosting]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hosting.id
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-rt-public"
  })
}

resource "aws_route_table" "application" {
  for_each = var.availability_zones

  vpc_id = aws_vpc.hosting.id
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-rt-app-${each.key}"
  })
}

# DESIGN: deliberately no internet, NAT or VPN default route for the database tier.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.hosting.id
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-rt-db"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.hosting.id
}

resource "aws_route" "application_internet" {
  for_each = var.availability_zones

  route_table_id         = aws_route_table.application[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.application_egress[var.single_nat_gateway ? "c" : each.key].id
}

resource "aws_route_table_association" "public" {
  for_each = var.availability_zones

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "application" {
  for_each = var.availability_zones

  subnet_id      = aws_subnet.application[each.key].id
  route_table_id = aws_route_table.application[each.key].id
}

resource "aws_route_table_association" "database" {
  for_each = var.availability_zones

  subnet_id      = aws_subnet.database[each.key].id
  route_table_id = aws_route_table.database.id
}
