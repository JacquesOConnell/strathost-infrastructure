mock_provider "aws" {
  override_during = plan
}
variables {
  environment           = "test"
  cost_center           = "InterviewSandbox"
  vpc_id                = "vpc-00000000000000001"
  private_zone_name     = "internal.example.com"
  internal_hostname     = "internal.example.com"
  checkmk_hostname      = "monitor.internal.example.com"
  internal_alb_dns_name = "internal-fixture.eu-west-1.elb.amazonaws.com"
  internal_alb_zone_id  = "Z0000000000000"
  checkmk_private_ip    = "10.0.3.30"
}
run "private_application_and_monitor_names" {
  command = plan
  assert {
    condition = (
      one(aws_route53_zone.private.vpc).vpc_id == var.vpc_id &&
      aws_route53_record.checkmk.records == toset(["10.0.3.30"]) &&
      one(aws_route53_record.internal_wordpress.alias).evaluate_target_health
    )
    error_message = "Keep administration DNS private and point WordPress at the internal ALB."
  }
}
