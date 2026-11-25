# Plan section 25.1: mocked configuration checks; these do not establish live traffic or IAM authorisation.
mock_provider "aws" {
  override_during = plan
}

variables {
  environment       = "test"
  vpc_id            = "vpc-00000000000000001"
  cost_center       = "InterviewSandbox"
  origin_test_cidrs = ["192.0.2.10/32"]
  vpn_client_cidrs  = ["198.51.100.10/32"]
}

override_resource {
  override_during = plan
  target          = aws_security_group.docker_hosts
  values          = { id = "sg-00000000000000004" }
}

override_resource {
  override_during = plan
  target          = aws_security_group.checkmk_server
  values          = { id = "sg-00000000000000008" }
}

run "restricted_service_flows" {
  command = plan

  assert {
    condition = (
      length(output.security_group_ids) == 8 &&
      aws_vpc_security_group_ingress_rule.application_proxy_public_alb.from_port == 8080 &&
      aws_vpc_security_group_ingress_rule.application_proxy_secure_alb.from_port == 8081 &&
      aws_vpc_security_group_ingress_rule.application_proxy_internal_alb.from_port == 8082 &&
      aws_vpc_security_group_ingress_rule.mysql_from_docker.referenced_security_group_id == aws_security_group.docker_hosts.id &&
      aws_vpc_security_group_ingress_rule.efs_from_docker.referenced_security_group_id == aws_security_group.docker_hosts.id
    )
    error_message = "Protected proxy ports must remain distinct and only Docker may initiate database or EFS sessions."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.vpn_private_https_internal_alb.cidr_ipv4 == "10.0.1.10/32" &&
      alltrue([for rule in [aws_vpc_security_group_ingress_rule.checkmk_agent_pull_docker_hosts, aws_vpc_security_group_ingress_rule.checkmk_agent_pull_vpn_server] :
        rule.from_port == 6556 && rule.referenced_security_group_id == aws_security_group.checkmk_server.id
      ]) &&
      alltrue([for rule in [aws_vpc_security_group_egress_rule.managed_https_docker_hosts, aws_vpc_security_group_egress_rule.managed_https_vpn_server, aws_vpc_security_group_egress_rule.managed_https_checkmk_server] :
        rule.ip_protocol == "tcp" && rule.from_port == 443 && rule.to_port == 443
      ])
    )
    error_message = "VPN and monitoring paths must retain their selected sources and ports."
  }
}

run "reject_world_open_vpn" {
  command = plan
  variables {
    vpn_client_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.vpn_client_cidrs]
}

run "reject_production_without_cloudflare" {
  command = plan
  variables {
    environment = "prod"
  }
  expect_failures = [var.cloudflare_enabled]
}

run "cloudflare_origin_range_replaces_test_client" {
  command = plan
  variables {
    environment           = "prod"
    cloudflare_enabled    = true
    cloudflare_ipv4_cidrs = ["173.245.48.0/20"]
    origin_test_cidrs     = []
  }
  assert {
    condition = (
      toset(keys(aws_vpc_security_group_ingress_rule.public_origin_https)) == toset(["173.245.48.0/20"]) &&
      toset(keys(aws_vpc_security_group_ingress_rule.secure_origin_https)) == toset(["173.245.48.0/20"])
    )
    error_message = "Enabled Cloudflare must use the versioned edge ranges instead of origin-test clients."
  }
}
