# The image IDs below are mock fixtures, not deployment examples.
mock_provider "aws" {
  override_during = plan
  mock_data "aws_ami" {
    defaults = { id = "ami-00000000000000001" }
  }
  mock_resource "aws_instance" {
    defaults = { availability_zone = "eu-west-1c" }
  }
}

variables {
  environment = "test"
  cost_center = "InterviewSandbox"
  public_subnet_ids = {
    a = "subnet-00000000000000001"
    b = "subnet-00000000000000002"
    c = "subnet-00000000000000003"
  }
  application_subnet_ids = {
    a = "subnet-00000000000000004"
    b = "subnet-00000000000000005"
    c = "subnet-00000000000000006"
  }
  docker_ami_id                 = "ami-00000000000000001"
  vpn_ami_id                    = "ami-00000000000000001"
  checkmk_ami_id                = "ami-00000000000000001"
  docker_security_group_id      = "sg-00000000000000001"
  vpn_security_group_id         = "sg-00000000000000002"
  checkmk_security_group_id     = "sg-00000000000000003"
  docker_instance_profile_name  = "fixture-docker-profile"
  vpn_instance_profile_name     = "fixture-vpn-profile"
  checkmk_instance_profile_name = "fixture-checkmk-profile"
  ebs_kms_key_arn               = "arn:aws:kms:eu-west-1:111122223333:key/fixture-ebs"
  bootstrap_user_data           = "#!/bin/bash\n# Non-executed mock bootstrap fixture\n"
}

run "diagram_host_placement" {
  command = plan
  assert {
    condition = (
      length(output.docker_instance_ids) == 3 &&
      aws_instance.docker_01.subnet_id == var.application_subnet_ids["a"] &&
      aws_instance.docker_02.subnet_id == var.application_subnet_ids["b"] &&
      aws_instance.docker_03.subnet_id == var.application_subnet_ids["c"] &&
      aws_instance.vpn_server.subnet_id == var.public_subnet_ids["a"] &&
      aws_instance.checkmk_server.subnet_id == var.public_subnet_ids["c"] &&
      !aws_instance.vpn_server.source_dest_check
    )
    error_message = "Keep the three fixed Docker hosts and the supplied VPN/Checkmk placements."
  }
  assert {
    condition = alltrue([
      for server in [aws_instance.docker_01, aws_instance.docker_02, aws_instance.docker_03, aws_instance.vpn_server, aws_instance.checkmk_server] :
      one(server.metadata_options).http_tokens == "required" && one(server.root_block_device).encrypted
    ])
    error_message = "All five hosts require IMDSv2 and encrypted root storage."
  }
  assert {
    condition = (
      !aws_instance.docker_01.associate_public_ip_address &&
      !aws_instance.docker_02.associate_public_ip_address &&
      !aws_instance.docker_03.associate_public_ip_address &&
      aws_instance.checkmk_server.associate_public_ip_address &&
      aws_ebs_volume.checkmk_data.encrypted && !aws_volume_attachment.checkmk_data.force_detach
    )
    error_message = "Keep Docker private and protect the Checkmk data attachment."
  }
}
