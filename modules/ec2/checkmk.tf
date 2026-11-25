# Diagram A07 / scope decision 3: one Checkmk host in public C, as supplied.
# Public IPv4 supplies outbound package/SSM access through the IGW; the SG does not expose its UI to the internet.
resource "aws_instance" "checkmk_server" {
  ami                                  = data.aws_ami.checkmk.id
  instance_type                        = "t3.medium"
  subnet_id                            = var.public_subnet_ids["c"]
  private_ip                           = "10.0.3.30"
  vpc_security_group_ids               = [var.checkmk_security_group_id]
  iam_instance_profile                 = var.checkmk_instance_profile_name
  associate_public_ip_address          = true
  source_dest_check                    = true
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
    volume_size           = var.environment == "prod" ? 50 : 30
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.resource_prefix}-ebs-checkmk-server-root" })
  }

  # Only SSM/bootstrap metadata belongs here; no passwords, private keys or secret values.
  user_data                   = var.bootstrap_user_data
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.resource_prefix}-ec2-checkmk-server", Role = "checkmk" })
}

# Plan 14.4: separate encrypted data disk. Configuration must wait for this attachment.
resource "aws_ebs_volume" "checkmk_data" {
  availability_zone = aws_instance.checkmk_server.availability_zone
  type              = "gp3"
  size              = var.environment == "prod" ? 50 : 20
  encrypted         = true
  kms_key_id        = var.ebs_kms_key_arn
  iops              = 3000
  throughput        = 125
  tags              = merge(local.tags, { Name = "${local.resource_prefix}-ebs-checkmk-data" })
}

resource "aws_volume_attachment" "checkmk_data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.checkmk_data.id
  instance_id                    = aws_instance.checkmk_server.id
  force_detach                   = false
  stop_instance_before_detaching = true
}
