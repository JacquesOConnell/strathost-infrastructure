mock_provider "aws" {
  override_during = plan
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}
variables {
  environment = "test"
  cost_center = "InterviewSandbox"
}
run "separate_machine_identities" {
  command = plan
  assert {
    condition = (
      length(output.role_names) == 4 && length(output.instance_profile_names) == 3 &&
      aws_iam_role.docker.name != aws_iam_role.checkmk.name &&
      aws_iam_role_policy_attachment.backup_service.role == aws_iam_role.backup.name &&
      aws_iam_role_policy_attachment.vpn_ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    )
    error_message = "Keep backup separate from instance profiles and workload identities."
  }
}
