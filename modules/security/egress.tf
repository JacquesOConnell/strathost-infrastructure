# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 8.2.
# Define initiated flows explicitly; stateful replies do not require ephemeral-port rules.

resource "aws_vpc_security_group_egress_rule" "application_proxy_public_alb" {
  security_group_id            = aws_security_group.public_alb.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Only the matching application proxy and health checks"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "application_proxy_secure_alb" {
  security_group_id            = aws_security_group.secure_alb.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Only the matching application proxy and health checks"
  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "application_proxy_internal_alb" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Only the matching application proxy and health checks"
  ip_protocol                  = "tcp"
  from_port                    = 8082
  to_port                      = 8082
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "docker_to_mysql" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.mysql.id
  description                  = "WordPress database sessions"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "docker_to_efs" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.wordpress_efs.id
  description                  = "Shared uploads through EFS mount targets"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "checkmk_agent_pull_docker_hosts" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Poll managed Checkmk agents"
  ip_protocol                  = "tcp"
  from_port                    = 6556
  to_port                      = 6556
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "checkmk_agent_pull_vpn_server" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.vpn_server.id
  description                  = "Poll managed Checkmk agents"
  ip_protocol                  = "tcp"
  from_port                    = 6556
  to_port                      = 6556
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "checkmk_receiver_docker_hosts" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.checkmk_server.id
  description                  = "Register with the Checkmk Agent Receiver"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  tags                         = local.tags
}

resource "aws_vpc_security_group_egress_rule" "checkmk_receiver_vpn_server" {
  security_group_id            = aws_security_group.vpn_server.id
  referenced_security_group_id = aws_security_group.checkmk_server.id
  description                  = "Register with the Checkmk Agent Receiver"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  tags                         = local.tags
}

# DESIGN: broad HTTPS is an explicit package/API exception; it does not filter destinations by hostname.
# This also covers registration HTTPS and S3, so duplicate egress rules are unnecessary.
resource "aws_vpc_security_group_egress_rule" "managed_https_docker_hosts" {
  security_group_id = aws_security_group.docker_hosts.id
  description       = "AWS APIs packages registries and approved HTTPS integrations"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "managed_https_vpn_server" {
  security_group_id = aws_security_group.vpn_server.id
  description       = "AWS APIs packages registries and approved HTTPS integrations"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "managed_https_checkmk_server" {
  security_group_id = aws_security_group.checkmk_server.id
  description       = "AWS APIs packages registries and approved HTTPS integrations"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}
