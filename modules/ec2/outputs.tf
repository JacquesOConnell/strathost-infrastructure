# Plan section 24: identifiers for target registration and the separate server configuration stage.
output "docker_instance_ids" {
  description = "The three fixed Docker hosts."
  value = {
    docker_01 = aws_instance.docker_01.id
    docker_02 = aws_instance.docker_02.id
    docker_03 = aws_instance.docker_03.id
  }
}
output "vpn_instance_id" {
  value = aws_instance.vpn_server.id
}
output "checkmk_instance_id" {
  value = aws_instance.checkmk_server.id
}
output "vpn_public_ip" {
  value = aws_eip.vpn.public_ip
}
output "checkmk_data_volume_id" {
  description = "Use this ID to identify the correct Nitro block device before formatting or mounting."
  value       = aws_ebs_volume.checkmk_data.id
}
output "private_ip_addresses" {
  value = {
    docker_01 = aws_instance.docker_01.private_ip
    docker_02 = aws_instance.docker_02.private_ip
    docker_03 = aws_instance.docker_03.private_ip
    vpn       = aws_instance.vpn_server.private_ip
    checkmk   = aws_instance.checkmk_server.private_ip
  }
}
