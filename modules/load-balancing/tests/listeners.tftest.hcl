mock_provider "aws" {
  override_during = plan
}
variables {
  environment                    = "test"
  cost_center                    = "InterviewSandbox"
  vpc_id                         = "vpc-00000000000000001"
  public_subnet_ids              = { a = "subnet-00000000000000001", b = "subnet-00000000000000002", c = "subnet-00000000000000003" }
  application_subnet_ids         = { a = "subnet-00000000000000004", b = "subnet-00000000000000005", c = "subnet-00000000000000006" }
  public_alb_security_group_id   = "sg-00000000000000001"
  secure_alb_security_group_id   = "sg-00000000000000002"
  internal_alb_security_group_id = "sg-00000000000000003"
  docker_instance_ids            = { docker_01 = "i-00000000000000001", docker_02 = "i-00000000000000002", docker_03 = "i-00000000000000003" }
  access_logs_bucket_name        = "strathost-test-euw1-alb-logs-111122223333"
  certificate_arns               = { for visibility in ["public", "secure", "internal"] : visibility => "arn:aws:acm:eu-west-1:111122223333:certificate/00000000-0000-0000-0000-000000000001" }
  hostnames                      = { public = "www.example.com", secure = "secure.example.com", internal = "internal.example.com" }
}
run "isolated_listeners_default_deny" {
  command = plan
  assert {
    condition = (
      !aws_lb.public_web.internal && !aws_lb.secure_web.internal && aws_lb.internal_web.internal &&
      aws_lb_target_group.public_wordpress.port == 8080 && aws_lb_target_group.secure_wordpress.port == 8081 &&
      aws_lb_target_group.internal_wordpress.port == 8082 && length(aws_lb_target_group_attachment.public_docker) == 3 &&
      length(aws_lb_target_group_attachment.secure_docker) == 3 && length(aws_lb_target_group_attachment.internal_docker) == 3 &&
      length(aws_lb_listener_rule.secure_hostname) == 0 &&
      one(one(aws_lb_listener.secure_https.default_action).fixed_response).status_code == "403"
    )
    error_message = "Separate all three workload paths and deny forwarding until configured."
  }
}
run "reject_unverified_secure_publication" {
  command = plan
  variables { enable_secure_routing = true }
  expect_failures = [var.enable_secure_routing]
}
