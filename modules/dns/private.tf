# Plan 15: internal names resolve only within the VPC or through the VPN DNS forwarder.
resource "aws_route53_zone" "private" {
  name          = var.private_zone_name
  comment       = "StratHost ${var.environment} private administration and application DNS"
  force_destroy = false
  vpc {
    vpc_id     = var.vpc_id
    vpc_region = "eu-west-1"
  }
  tags = {
    Name        = "strathost-${var.environment}-euw1-private-dns", Project = "StratHost",
    Environment = var.environment, ManagedBy = "Terraform", CostCenter = var.cost_center,
    Owner       = "Infrastructure", Application = "WordPressHosting", BusinessUnit = "StratHost",
    Repository  = "strathost-infrastructure", DataClassification = "Confidential",
    Criticality = var.environment == "prod" ? "High" : "Standard", BackupPolicy = "none"
  }
}
resource "aws_route53_record" "internal_wordpress" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.internal_hostname
  type    = "A"
  alias {
    name                   = var.internal_alb_dns_name
    zone_id                = var.internal_alb_zone_id
    evaluate_target_health = true
  }
}
resource "aws_route53_record" "checkmk" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.checkmk_hostname
  type    = "A"
  ttl     = 60
  records = [var.checkmk_private_ip]
}
