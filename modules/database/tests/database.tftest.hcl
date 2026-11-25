# Plan 25: configuration tests use mocks; no AWS database is created.
mock_provider "aws" {
  override_during = plan
  mock_resource "aws_db_instance" {
    defaults = {
      address = "fixture-db.example.invalid"
      master_user_secret = [{
        kms_key_id    = "arn:aws:kms:eu-west-1:111122223333:key/fixture"
        secret_arn    = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:fixture-admin"
        secret_status = "active"
      }]
    }
  }
}

variables {
  environment             = "test"
  cost_center             = "InterviewSandbox"
  database_subnet_ids     = ["subnet-00000000000000007", "subnet-00000000000000008", "subnet-00000000000000009"]
  mysql_security_group_id = "sg-00000000000000001"
  rds_kms_key_arn         = "arn:aws:kms:eu-west-1:111122223333:key/fixture-rds"
  secrets_kms_key_arn     = "arn:aws:kms:eu-west-1:111122223333:key/fixture-secrets"
  logs_kms_key_arn        = "arn:aws:kms:eu-west-1:111122223333:key/fixture-logs"
  final_snapshot_suffix   = "validation-20261125"
}

run "private_primary_and_standby" {
  command = plan
  assert {
    condition = (
      aws_db_instance.wordpress.multi_az && !aws_db_instance.wordpress.publicly_accessible &&
      aws_db_instance.wordpress.storage_encrypted && aws_db_instance.wordpress.manage_master_user_password &&
      !aws_db_instance.wordpress.skip_final_snapshot && !aws_db_instance.wordpress.delete_automated_backups &&
      length(aws_db_subnet_group.wordpress.subnet_ids) == 3
    )
    error_message = "The database must preserve the private encrypted primary/standby design and managed credentials."
  }
}

run "production_keeps_final_snapshot" {
  command = plan
  variables {
    environment         = "prod"
    skip_final_snapshot = true
  }
  expect_failures = [var.skip_final_snapshot]
}

run "reject_incomplete_database_tier" {
  command = plan
  variables {
    database_subnet_ids = ["subnet-00000000000000007"]
  }
  expect_failures = [var.database_subnet_ids]
}
