# Plan 16 / A04: internal traffic has its own ALB, group, listener and proxy port.
resource "aws_lb" "internal_web" {
  name                       = "${local.resource_prefix}-alb-internal"
  internal                   = true
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = values(var.application_subnet_ids)
  security_groups            = [var.internal_alb_security_group_id]
  enable_deletion_protection = var.environment == "prod"
  enable_http2               = true
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
  idle_timeout               = 60
  xff_header_processing_mode = "append"
  access_logs {
    enabled = true
    bucket  = var.access_logs_bucket_name
    prefix  = "alb/internal"
  }
  tags = merge(local.tags, { Name = "${local.resource_prefix}-alb-internal" })
}

resource "aws_lb_target_group" "internal_wordpress" {
  name                              = "${local.resource_prefix}-tg-internal"
  vpc_id                            = var.vpc_id
  target_type                       = "instance"
  protocol                          = "HTTP"
  protocol_version                  = "HTTP1"
  port                              = 8082
  deregistration_delay              = 60
  slow_start                        = 30
  load_balancing_algorithm_type     = "round_robin"
  load_balancing_cross_zone_enabled = "true"
  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }
  tags = merge(local.tags, { Name = "${local.resource_prefix}-internal-web" })
}

# One simple loop registers the three fixed Docker hosts with this site's group.
resource "aws_lb_target_group_attachment" "internal_docker" {
  for_each         = var.docker_instance_ids
  target_group_arn = aws_lb_target_group.internal_wordpress.arn
  target_id        = each.value
  port             = 8082
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal_web.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arns["internal"]
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }
  tags = merge(local.tags, { Name = "${local.resource_prefix}-internal-web" })
}

# Publishing is a separate reviewed action after health/access tests.
resource "aws_lb_listener_rule" "internal_hostname" {
  count        = var.enable_internal_routing ? 1 : 0
  listener_arn = aws_lb_listener.internal_https.arn
  priority     = 100
  condition {
    host_header {
      values = [var.hostnames["internal"]]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_wordpress.arn
  }
  tags = merge(local.tags, { Name = "${local.resource_prefix}-internal-web" })
}
