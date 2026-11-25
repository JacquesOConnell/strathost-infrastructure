# Offline wiring test only: policy-document mocks do not establish effective IAM permissions.
mock_provider "aws" {
  override_during = plan
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"test:Fixture\",\"Resource\":\"*\"}]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"]
    }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-00000000000000001" }
  }
  mock_resource "aws_instance" {
    defaults = { availability_zone = "eu-west-1c" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:rds-admin-fixture"
        secret_status = "active"
        kms_key_id    = "arn:aws:kms:eu-west-1:111122223333:key/fixture-secrets"
      }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/fixture-machine" }
  }
}
variables {
  environment                 = "test"
  expected_account_id         = "111122223333"
  cost_center                 = "InterviewSandbox"
  availability_zones          = { a = "eu-west-1a", b = "eu-west-1b", c = "eu-west-1c" }
  docker_ami_id               = "ami-00000000000000001"
  vpn_ami_id                  = "ami-00000000000000001"
  checkmk_ami_id              = "ami-00000000000000001"
  key_administrator_role_arns = ["arn:aws:iam::111122223333:role/fixture-key-admin"]
  recovery_role_arn           = "arn:aws:iam::111122223333:role/fixture-recovery"
  vpn_client_cidrs            = ["198.51.100.10/32"]
  certificate_arns            = { for visibility in ["public", "secure", "internal"] : visibility => "arn:aws:acm:eu-west-1:111122223333:certificate/00000000-0000-0000-0000-000000000001" }
  hostnames                   = { public = "www.example.com", secure = "secure.example.com", internal = "internal.example.com" }
  private_dns_zone_name       = "internal.example.com"
  checkmk_hostname            = "monitor.internal.example.com"
  final_snapshot_suffix       = "test-release-001"
  ssm_artifact_bucket_arns    = ["arn:aws:s3:::fixture-ssm-artifacts-eu-west-1"]
}
run "connect_supplied_services_without_publishing" {
  command = plan
  override_resource {
    target          = module.storage.aws_efs_file_system.wordpress
    values          = { arn = "arn:aws:elasticfilesystem:eu-west-1:111122223333:file-system/fs-00000000000000001" }
    override_during = plan
  }
  override_resource {
    target          = module.ec2.aws_instance.docker_01
    values          = { id = "i-00000000000000001" }
    override_during = plan
  }
  override_resource {
    target          = module.ec2.aws_instance.docker_02
    values          = { id = "i-00000000000000002" }
    override_during = plan
  }
  override_resource {
    target          = module.ec2.aws_instance.docker_03
    values          = { id = "i-00000000000000003" }
    override_during = plan
  }
  override_resource {
    target          = module.ec2.aws_instance.vpn_server
    values          = { id = "i-00000000000000004" }
    override_during = plan
  }
  override_resource {
    target          = module.ec2.aws_instance.checkmk_server
    values          = { id = "i-00000000000000005" }
    override_during = plan
  }
  assert {
    condition = (
      length(output.docker_instance_ids) == 3 && length(output.private_ip_addresses) == 5 &&
      length(output.site_secret_arns) == 3 && length(output.efs_access_points) == 3 &&
      output.private_ip_addresses.checkmk == "10.0.3.30" &&
      length(module.backup.selected_resource_arns) == 6 &&
      output.account_id == var.expected_account_id && !var.enable_secure_routing
    )
    error_message = "Composition must preserve the fixed fleet, shared storage, explicit backup selection and staged publication."
  }
}
