# Plan section 25.1: mocked configuration checks; these do not establish live traffic or IAM authorisation.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-west-1:111122223333:key/00000000-0000-4000-8000-000000000001"
      key_id = "00000000-0000-4000-8000-000000000001"
    }
  }
}

variables {
  expected_account_id         = "111122223333"
  cost_center                 = "InterviewSandbox"
  key_administrator_role_arns = ["arn:aws:iam::111122223333:role/StateAdministrator"]
  additional_tags             = { Project = "CannotOverrideRequiredTag" }
  backend_access = {
    test = {
      role_arn   = "arn:aws:iam::111122223333:role/TestDeployment"
      state_keys = ["environments/test/terraform.tfstate"]
    }
  }
}

run "state_storage_controls" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket.terraform_state.bucket == "strathost-tfstate-111122223333-euw1" &&
      !aws_s3_bucket.terraform_state.force_destroy &&
      aws_s3_bucket_public_access_block.terraform_state.block_public_acls &&
      aws_s3_bucket_public_access_block.terraform_state.block_public_policy &&
      aws_s3_bucket_public_access_block.terraform_state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.terraform_state.restrict_public_buckets &&
      aws_kms_key.terraform_state.enable_key_rotation &&
      aws_kms_key.terraform_state.deletion_window_in_days == 30
    )
    error_message = "State storage must be private, non-force-destructible and protected by a rotating key."
  }

  assert {
    condition = (
      one(aws_s3_bucket_versioning.terraform_state.versioning_configuration).status == "Enabled" &&
      one(aws_s3_bucket_ownership_controls.terraform_state.rule).object_ownership == "BucketOwnerEnforced" &&
      local.required_tags.Project == "StratHost" &&
      output.workload_backend_configuration.use_lockfile
    )
    error_message = "Versioning, ownership, governance tags and native locking must remain enabled."
  }
}

run "reject_wildcard_backend_keys" {
  command = plan
  variables {
    backend_access = {
      test = {
        role_arn   = "arn:aws:iam::111122223333:role/TestDeployment"
        state_keys = ["environments/*"]
      }
    }
  }
  expect_failures = [var.backend_access]
}

run "reject_cross_account_backend_role" {
  command = plan
  variables {
    backend_access = {
      test = {
        role_arn   = "arn:aws:iam::444455556666:role/TestDeployment"
        state_keys = ["environments/test/terraform.tfstate"]
      }
    }
  }
  expect_failures = [var.backend_access]
}
