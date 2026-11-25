mock_provider "aws" {
  override_during = plan
}
variables {
  environment         = "test"
  cost_center         = "InterviewSandbox"
  backup_kms_key_arn  = "arn:aws:kms:eu-west-1:111122223333:key/fixture-backup"
  backup_role_arn     = "arn:aws:iam::111122223333:role/fixture-backup"
  efs_file_system_arn = "arn:aws:elasticfilesystem:eu-west-1:111122223333:file-system/fs-00000000000000001"
  instance_arns       = [for number in range(1, 6) : "arn:aws:ec2:eu-west-1:111122223333:instance/i-0000000000000000${number}"]
}
run "daily_explicit_resource_selection" {
  command = plan
  assert {
    condition = (
      length(output.selected_resource_arns) == 6 &&
      !aws_backup_vault.workloads.force_destroy &&
      one(aws_backup_plan.workloads.rule).schedule == "cron(0 1 * * ? *)" &&
      one(one(aws_backup_plan.workloads.rule).lifecycle).delete_after == 2
    )
    error_message = "Back up all five EC2 hosts and EFS once per day in a protected vault."
  }
}
