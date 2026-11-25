output "role_arns" {
  description = "Service roles for resource and key policy composition."
  value = {
    docker  = aws_iam_role.docker.arn
    vpn     = aws_iam_role.vpn.arn
    checkmk = aws_iam_role.checkmk.arn
    backup  = aws_iam_role.backup.arn
  }
}
output "role_names" {
  value = {
    docker  = aws_iam_role.docker.name
    vpn     = aws_iam_role.vpn.name
    checkmk = aws_iam_role.checkmk.name
    backup  = aws_iam_role.backup.name
  }
}
output "instance_profile_names" {
  value = {
    docker  = aws_iam_instance_profile.docker.name
    vpn     = aws_iam_instance_profile.vpn.name
    checkmk = aws_iam_instance_profile.checkmk.name
  }
}
