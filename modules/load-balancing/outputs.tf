output "dns_names" {
  description = "Origin DNS names; public DNS publication is a later step."
  value = {
    public   = aws_lb.public_web.dns_name
    secure   = aws_lb.secure_web.dns_name
    internal = aws_lb.internal_web.dns_name
  }
}
output "zone_ids" {
  description = "ALB hosted-zone IDs for alias records."
  value = {
    public   = aws_lb.public_web.zone_id
    secure   = aws_lb.secure_web.zone_id
    internal = aws_lb.internal_web.zone_id
  }
}
output "target_group_arns" {
  value = {
    public   = aws_lb_target_group.public_wordpress.arn
    secure   = aws_lb_target_group.secure_wordpress.arn
    internal = aws_lb_target_group.internal_wordpress.arn
  }
}
