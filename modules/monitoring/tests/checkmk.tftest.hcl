# These tests verify inventory and the role-policy attachment, not live Checkmk services.
mock_provider "aws" {
  override_during = plan
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  vpc_id              = "vpc-00000000000000001"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:111122223333:key/fixture-logs"
  cost_center         = "InterviewSandbox"
  environment         = "test"
  expected_account_id = "111122223333"
  checkmk_role_name   = "fixture-checkmk-role"
  private_ip_addresses = {
    docker_01 = "10.0.4.10"
    docker_02 = "10.0.5.10"
    docker_03 = "10.0.6.10"
    vpn       = "10.0.1.10"
    checkmk   = "10.0.3.30"
  }
}

run "checkmk_inventory_and_instance_role" {
  command = plan
  assert {
    condition = (
      length(output.host_inventory.hosts) == 5 &&
      output.host_inventory.hosts["strathost-test-euw1-checkmk"] == "127.0.0.1" &&
      output.host_inventory.aws_host == "strathost-test-euw1-aws" &&
      aws_iam_role_policy.checkmk_aws.role == "fixture-checkmk-role"
    )
    error_message = "Checkmk must monitor the five servers and use its assigned instance role."
  }
}
