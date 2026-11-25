# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 6.1 and 7.2; decisions D02.
# Adopt defaults only in this new VPC; workload security groups enforce the selected traffic policy.

resource "aws_default_security_group" "quarantined" {
  vpc_id  = aws_vpc.hosting.id
  ingress = []
  egress  = []
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-quarantine"
  })
}

# DESIGN: an accidentally unassociated subnet must not inherit internet or VPN routes.
resource "aws_default_route_table" "quarantined" {
  default_route_table_id = aws_vpc.hosting.default_route_table_id
  route                  = []
  propagating_vgws       = []
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-rt-quarantine"
  })
}

# MASTER / D02: retain allow-all IPv4 NACLs; dedicated security groups are the enforcement boundary.
# Initial adoption replaces ACL rules, so complete it before workload traffic exists.
resource "aws_default_network_acl" "hosting" {
  default_network_acl_id = aws_vpc.hosting.default_network_acl_id
  subnet_ids = concat(
    [for subnet in aws_subnet.public : subnet.id],
    [for subnet in aws_subnet.application : subnet.id],
    [for subnet in aws_subnet.database : subnet.id]
  )

  ingress {
    rule_no    = 100
    protocol   = -1
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = -1
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-nacl-default"
  })
}
