# Diagram A06 / plan 14: one VPN host in public A, with a separately associated EIP.
resource "aws_instance" "vpn_server" {
  ami                                  = data.aws_ami.vpn.id
  instance_type                        = var.environment == "prod" ? "t3.small" : "t3.micro"
  subnet_id                            = var.public_subnet_ids["a"]
  private_ip                           = "10.0.1.10"
  vpc_security_group_ids               = [var.vpn_security_group_id]
  iam_instance_profile                 = var.vpn_instance_profile_name
  associate_public_ip_address          = false
  source_dest_check                    = false
  monitoring                           = false
  disable_api_termination              = var.protect_instances
  instance_initiated_shutdown_behavior = "stop"
  ebs_optimized                        = true

  # Host processes use the role. Bridged application containers do not receive IMDS credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  credit_specification {
    cpu_credits = "standard"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.environment == "prod" ? 20 : 15
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.resource_prefix}-ebs-vpn-server-root" })
  }

  # Only SSM/bootstrap metadata belongs here; no passwords, private keys or secret values.
  user_data                   = var.bootstrap_user_data
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.resource_prefix}-ec2-vpn-server", Role = "vpn" })
}

resource "aws_eip" "vpn" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.resource_prefix}-eip-vpn" })
}

resource "aws_eip_association" "vpn" {
  allocation_id      = aws_eip.vpn.id
  instance_id        = aws_instance.vpn_server.id
  private_ip_address = "10.0.1.10"
}
