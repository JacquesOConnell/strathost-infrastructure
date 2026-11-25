# Plan section 24: return the group IDs needed by the other service modules.
output "security_group_ids" {
  description = "Dedicated security groups by server or service role."
  value = {
    public_alb     = aws_security_group.public_alb.id
    secure_alb     = aws_security_group.secure_alb.id
    internal_alb   = aws_security_group.internal_alb.id
    docker_hosts   = aws_security_group.docker_hosts.id
    mysql          = aws_security_group.mysql.id
    wordpress_efs  = aws_security_group.wordpress_efs.id
    vpn_server     = aws_security_group.vpn_server.id
    checkmk_server = aws_security_group.checkmk_server.id
  }
}
