# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 8.2.
# Allow only the source, destination and port combinations in the traffic contract.

# DESIGN: origin CIDRs restrict transport; mTLS and application authentication remain separate controls.
resource "aws_vpc_security_group_ingress_rule" "public_origin_https" {
  for_each = local.origin_cidrs

  security_group_id = aws_security_group.public_alb.id
  description       = "HTTPS from the approved public origin ranges"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "secure_origin_https" {
  for_each = local.origin_cidrs

  security_group_id = aws_security_group.secure_alb.id
  description       = "HTTPS from the approved protected origin ranges"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "wireguard_clients" {
  for_each = var.vpn_client_cidrs

  security_group_id = aws_security_group.vpn_server.id
  description       = "WireGuard transport from an approved client range"
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
  tags              = local.tags
}

# Plan D01: public, secure and internal traffic use separate proxy ports.
resource "aws_vpc_security_group_ingress_rule" "application_proxy_public_alb" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.public_alb.id
  description                  = "Dedicated public_alb application proxy"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "application_proxy_secure_alb" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.secure_alb.id
  description                  = "Dedicated secure_alb application proxy"
  ip_protocol                  = "tcp"
  from_port                    = 8081
  to_port                      = 8081
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "application_proxy_internal_alb" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.internal_alb.id
  description                  = "Dedicated internal_alb application proxy"
  ip_protocol                  = "tcp"
  from_port                    = 8082
  to_port                      = 8082
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_docker" {
  security_group_id            = aws_security_group.mysql.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "MySQL TLS sessions from WordPress containers"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_docker" {
  security_group_id            = aws_security_group.wordpress_efs.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "NFS through the TLS and IAM EFS mount helper"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_agent_pull_docker_hosts" {
  security_group_id            = aws_security_group.docker_hosts.id
  referenced_security_group_id = aws_security_group.checkmk_server.id
  description                  = "TLS Checkmk agent pull from the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 6556
  to_port                      = 6556
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_agent_pull_vpn_server" {
  security_group_id            = aws_security_group.vpn_server.id
  referenced_security_group_id = aws_security_group.checkmk_server.id
  description                  = "TLS Checkmk agent pull from the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 6556
  to_port                      = 6556
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_registration_https_docker_hosts" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Checkmk REST registration from a managed host"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_registration_https_vpn_server" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.vpn_server.id
  description                  = "Checkmk REST registration from a managed host"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_receiver_docker_hosts" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.docker_hosts.id
  description                  = "Checkmk Agent Receiver registration"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "checkmk_receiver_vpn_server" {
  security_group_id            = aws_security_group.checkmk_server.id
  referenced_security_group_id = aws_security_group.vpn_server.id
  description                  = "Checkmk Agent Receiver registration"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  tags                         = local.tags
}

# DESIGN / D04: this /32 must match WireGuard SNAT on the fixed VPN instance address.
resource "aws_vpc_security_group_ingress_rule" "vpn_private_https_internal_alb" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "Approved VPN HTTPS after SNAT on the fixed VPN address"
  cidr_ipv4         = "10.0.1.10/32"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "vpn_private_https_checkmk_server" {
  security_group_id = aws_security_group.checkmk_server.id
  description       = "Approved VPN HTTPS after SNAT on the fixed VPN address"
  cidr_ipv4         = "10.0.1.10/32"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "internal_synthetic_https" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.checkmk_server.id
  description                  = "Internal HTTPS synthetic monitoring"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  tags                         = local.tags
}
