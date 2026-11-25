# Diagram A05 / plan 14: three fixed Docker hosts, one in each application AZ. No Auto Scaling Group.
resource "aws_instance" "docker_01" {
  ami                                  = data.aws_ami.docker.id
  instance_type                        = var.environment == "prod" ? "t3.large" : "t3.small"
  subnet_id                            = var.application_subnet_ids["a"]
  private_ip                           = "10.0.4.10"
  vpc_security_group_ids               = [var.docker_security_group_id]
  iam_instance_profile                 = var.docker_instance_profile_name
  associate_public_ip_address          = false
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
    volume_size           = var.environment == "prod" ? 50 : 20
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.resource_prefix}-ebs-docker-01-root" })
  }

  # Only SSM/bootstrap metadata belongs here; no passwords, private keys or secret values.
  user_data                   = var.bootstrap_user_data
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.resource_prefix}-ec2-docker-01", Role = "docker" })
}

resource "aws_instance" "docker_02" {
  ami                                  = data.aws_ami.docker.id
  instance_type                        = var.environment == "prod" ? "t3.large" : "t3.small"
  subnet_id                            = var.application_subnet_ids["b"]
  private_ip                           = "10.0.5.10"
  vpc_security_group_ids               = [var.docker_security_group_id]
  iam_instance_profile                 = var.docker_instance_profile_name
  associate_public_ip_address          = false
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
    volume_size           = var.environment == "prod" ? 50 : 20
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.resource_prefix}-ebs-docker-02-root" })
  }

  # Only SSM/bootstrap metadata belongs here; no passwords, private keys or secret values.
  user_data                   = var.bootstrap_user_data
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.resource_prefix}-ec2-docker-02", Role = "docker" })
}

resource "aws_instance" "docker_03" {
  ami                                  = data.aws_ami.docker.id
  instance_type                        = var.environment == "prod" ? "t3.large" : "t3.small"
  subnet_id                            = var.application_subnet_ids["c"]
  private_ip                           = "10.0.6.10"
  vpc_security_group_ids               = [var.docker_security_group_id]
  iam_instance_profile                 = var.docker_instance_profile_name
  associate_public_ip_address          = false
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
    volume_size           = var.environment == "prod" ? 50 : 20
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.resource_prefix}-ebs-docker-03-root" })
  }

  # Only SSM/bootstrap metadata belongs here; no passwords, private keys or secret values.
  user_data                   = var.bootstrap_user_data
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.resource_prefix}-ec2-docker-03", Role = "docker" })
}
