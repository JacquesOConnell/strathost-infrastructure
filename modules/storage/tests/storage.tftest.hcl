# Plan section 25.1: mocked configuration checks; these do not establish live traffic or IAM authorisation.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::fixture-bucket" }
  }

  mock_resource "aws_efs_file_system" {
    defaults = {
      id  = "fs-00000000000000001"
      arn = "arn:aws:elasticfilesystem:eu-west-1:111122223333:file-system/fs-00000000000000001"
    }
  }

  mock_resource "aws_efs_access_point" {
    defaults = {
      id  = "fsap-00000000000000001"
      arn = "arn:aws:elasticfilesystem:eu-west-1:111122223333:access-point/fsap-00000000000000001"
    }
  }
}

variables {
  environment         = "test"
  expected_account_id = "111122223333"
  cost_center         = "InterviewSandbox"
  efs_kms_key_arn     = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-4000-8000-000000000001"
  exports_kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-4000-8000-000000000002"
  application_subnet_ids = {
    a = "subnet-00000000000000001"
    b = "subnet-00000000000000002"
    c = "subnet-00000000000000003"
  }
  efs_security_group_id   = "sg-00000000000000001"
  docker_runtime_role_arn = "arn:aws:iam::111122223333:role/DockerRuntime"
  recovery_role_arn       = "arn:aws:iam::111122223333:role/RecoveryOperator"
}

run "private_storage_and_site_access_points" {
  command = plan

  assert {
    condition = (
      length(output.bucket_names) == 2 &&
      alltrue([for bucket in [aws_s3_bucket.workload_exports, aws_s3_bucket.alb_access_logs] : !bucket.force_destroy]) &&
      alltrue([for block in aws_s3_bucket_public_access_block.workload :
        block.block_public_acls && block.block_public_policy && block.ignore_public_acls && block.restrict_public_buckets
      ]) &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.workload_exports.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms" &&
      one(one(aws_s3_bucket_server_side_encryption_configuration.alb_access_logs.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    )
    error_message = "Buckets must remain private and non-force-destructible with separate export and ALB-log encryption."
  }

  assert {
    condition = (
      aws_efs_file_system.wordpress.encrypted &&
      aws_efs_file_system.wordpress.throughput_mode == "elastic" &&
      length(aws_efs_mount_target.wordpress) == 3 &&
      length(aws_efs_access_point.site) == 3 &&
      one(aws_efs_access_point.site["secure_wordpress"].root_directory).path == "/sites/secure_wordpress" &&
      one(aws_efs_access_point.site["secure_wordpress"].posix_user).uid == 10002 &&
      one(aws_efs_backup_policy.wordpress.backup_policy).status == "DISABLED"
    )
    error_message = "EFS must remain encrypted and Regional with three mount targets, stable site identities and no duplicate automatic backup plan."
  }
}

run "reject_duplicate_site_identity" {
  command = plan
  variables {
    site_posix_ids = {
      public_wordpress = 10001
      secure_wordpress = 10001
    }
  }
  expect_failures = [var.site_posix_ids]
}

run "reject_runtime_role_as_recovery_role" {
  command = plan
  variables {
    recovery_role_arn = "arn:aws:iam::111122223333:role/DockerRuntime"
  }
  expect_failures = [var.recovery_role_arn]
}

run "diagram_does_not_require_custom_origin_trust" {
  command = plan
  variables {
    environment = "prod"
  }
  assert {
    condition     = length(aws_s3_bucket.origin_trust) == 0 && output.origin_ca_object == null
    error_message = "The diagram baseline must not require an additional origin trust bucket."
  }
}
