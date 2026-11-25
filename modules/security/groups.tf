# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 4 and 8.1.
# Keep each workload role in a dedicated group so traffic boundaries remain visible.

locals {
  resource_prefix = "strathost-${var.environment}-euw1"

  # Plan 8: use the approved Cloudflare ranges, or the explicit test client ranges.
  origin_cidrs = var.cloudflare_enabled ? var.cloudflare_ipv4_cidrs : var.origin_test_cidrs
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

# Rule ownership is standalone; do not add inline ingress/egress alongside the separate rule resources.
resource "aws_security_group" "public_alb" {
  name                   = "${local.resource_prefix}-sg-public-alb"
  description            = "HTTPS origins for public WordPress sites"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-public-alb"
  })
}

resource "aws_security_group" "secure_alb" {
  name                   = "${local.resource_prefix}-sg-secure-alb"
  description            = "HTTPS origins for authenticated WordPress sites"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-secure-alb"
  })
}

resource "aws_security_group" "internal_alb" {
  name                   = "${local.resource_prefix}-sg-internal-alb"
  description            = "Private HTTPS accessed through WireGuard or Checkmk"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-internal-alb"
  })
}

resource "aws_security_group" "docker_hosts" {
  name                   = "${local.resource_prefix}-sg-docker-hosts"
  description            = "Docker proxies and local monitoring agents"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-docker-hosts"
  })
}

resource "aws_security_group" "mysql" {
  name                   = "${local.resource_prefix}-sg-mysql"
  description            = "Private MySQL accessed only by Docker hosts"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-mysql"
  })
}

resource "aws_security_group" "wordpress_efs" {
  name                   = "${local.resource_prefix}-sg-wordpress-efs"
  description            = "Shared WordPress uploads accessed only by Docker hosts"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-wordpress-efs"
  })
}

resource "aws_security_group" "vpn_server" {
  name                   = "${local.resource_prefix}-sg-vpn-server"
  description            = "WireGuard transport and monitoring agent"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-vpn-server"
  })
}

resource "aws_security_group" "checkmk_server" {
  name                   = "${local.resource_prefix}-sg-checkmk-server"
  description            = "Private Checkmk dashboard and agent registration"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-sg-checkmk-server"
  })
}
