# Plan section 25.1: mocked configuration checks; these do not establish live traffic or IAM authorisation.
mock_provider "aws" {
  override_during = plan

}

variables {
  environment = "test"
  cost_center = "InterviewSandbox"
  key_policy_json = {
    for purpose in ["ebs", "rds", "efs", "backup", "exports", "secrets", "logs"] :
    purpose => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "TestFixtureOnlyNotADeploymentPolicy"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::111122223333:root" }
        Action    = "kms:*"
        Resource  = "*"
      }]
    })
  }
}

run "separate_rotating_service_keys" {
  command = plan
  assert {
    condition = (
      length(output.key_arns) == 7 &&
      length(output.key_ids) == 7 &&
      alltrue([for key in [aws_kms_key.ebs, aws_kms_key.rds, aws_kms_key.efs, aws_kms_key.backup, aws_kms_key.exports, aws_kms_key.secrets, aws_kms_key.logs] :
        key.enable_key_rotation && key.deletion_window_in_days == 30 &&
        !key.multi_region && key.customer_master_key_spec == "SYMMETRIC_DEFAULT"
      ]) &&
      aws_kms_alias.efs.name == "alias/strathost/test/efs"
    )
    error_message = "All seven service keys must retain rotation, deletion delay and deterministic purpose aliases."
  }
}

run "reject_empty_policy_documents" {
  command = plan
  variables {
    key_policy_json = {
      for purpose in ["ebs", "rds", "efs", "backup", "exports", "secrets", "logs"] :
      purpose => "{}"
    }
  }
  expect_failures = [var.key_policy_json]
}
