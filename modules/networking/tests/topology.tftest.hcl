# Plan section 25.1: mocked configuration checks; these do not establish live traffic or IAM authorisation.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"]
    }
  }

  mock_resource "aws_vpc" {
    defaults = {
      id                     = "vpc-00000000000000001"
      default_route_table_id = "rtb-00000000000000001"
      default_network_acl_id = "acl-00000000000000001"
    }
  }
}

variables {
  environment        = "test"
  cost_center        = "InterviewSandbox"
  single_nat_gateway = true
  availability_zones = {
    a = "eu-west-1a"
    b = "eu-west-1b"
    c = "eu-west-1c"
  }
  s3_endpoint_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::amazon-ssm-eu-west-1/*"
    }]
  })
  additional_tags = { Project = "CannotOverrideRequiredTag" }
}

override_resource {
  override_during = plan
  target          = aws_nat_gateway.application_egress["c"]
  values          = { id = "nat-00000000000000003" }
}

override_resource {
  override_during = plan
  target          = aws_route_table.database
  values          = { id = "rtb-00000000000000009" }
}

override_resource {
  override_during = plan
  target          = aws_route_table.public
  values          = { id = "rtb-00000000000000001" }
}

override_resource {
  override_during = plan
  target          = aws_route_table.application["a"]
  values          = { id = "rtb-00000000000000004" }
}

override_resource {
  override_during = plan
  target          = aws_route_table.application["b"]
  values          = { id = "rtb-00000000000000005" }
}

override_resource {
  override_during = plan
  target          = aws_route_table.application["c"]
  values          = { id = "rtb-00000000000000006" }
}

run "test_network_preserves_tiers_and_isolation" {
  command = plan

  assert {
    condition = (
      aws_vpc.hosting.cidr_block == "10.0.0.0/16" &&
      length(aws_subnet.public) == 3 &&
      length(aws_subnet.application) == 3 &&
      length(aws_subnet.database) == 3 &&
      length(distinct(concat(
        [for subnet in aws_subnet.public : subnet.cidr_block],
        [for subnet in aws_subnet.application : subnet.cidr_block],
        [for subnet in aws_subnet.database : subnet.cidr_block]
      ))) == 9
    )
    error_message = "The diagram requires three distinct subnets in each of three tiers."
  }

  assert {
    condition = alltrue(concat(
      [for subnet in aws_subnet.public : !subnet.map_public_ip_on_launch],
      [for subnet in aws_subnet.application : !subnet.map_public_ip_on_launch],
      [for subnet in aws_subnet.database : !subnet.map_public_ip_on_launch]
    ))
    error_message = "No subnet may automatically allocate public instance addresses."
  }

  assert {
    condition = (
      toset(keys(aws_nat_gateway.application_egress)) == toset(["c"]) &&
      alltrue([for route in aws_route.application_internet : route.nat_gateway_id == "nat-00000000000000003"])
    )
    error_message = "The single-NAT profile must route all applications through NAT C."
  }

  assert {
    condition = (
      aws_route.public_internet.route_table_id != aws_route_table.database.id &&
      alltrue([for route in aws_route.application_internet : route.route_table_id != aws_route_table.database.id]) &&
      !contains(aws_vpc_endpoint.s3.route_table_ids, aws_route_table.database.id)
    )
    error_message = "The database route table must not receive internet or S3 endpoint routes."
  }

  assert {
    condition = (
      length(aws_default_security_group.quarantined.ingress) == 0 &&
      length(aws_default_security_group.quarantined.egress) == 0 &&
      length(aws_default_route_table.quarantined.route) == 0 &&
      aws_vpc.hosting.tags.Project == "StratHost"
    )
    error_message = "Default objects must remain quarantined and required tags must take precedence."
  }
}

run "production_routes_use_same_zone_nat" {
  command = plan

  variables {
    environment        = "prod"
    single_nat_gateway = false
    cost_center        = "ApprovedProductionCostCenter"
  }

  override_resource {
    override_during = plan
    target          = aws_nat_gateway.application_egress["a"]
    values          = { id = "nat-00000000000000001" }
  }

  override_resource {
    override_during = plan
    target          = aws_nat_gateway.application_egress["b"]
    values          = { id = "nat-00000000000000002" }
  }

  assert {
    condition = (
      length(aws_nat_gateway.application_egress) == 3 &&
      aws_route.application_internet["a"].nat_gateway_id == "nat-00000000000000001" &&
      aws_route.application_internet["b"].nat_gateway_id == "nat-00000000000000002" &&
      aws_route.application_internet["c"].nat_gateway_id == "nat-00000000000000003"
    )
    error_message = "Production must use three NATs with same-AZ application routes."
  }
}

run "diagram_single_nat_remains_available" {
  command = plan
  variables {
    environment        = "prod"
    single_nat_gateway = true
  }
  assert {
    condition     = toset(keys(aws_nat_gateway.application_egress)) == toset(["c"])
    error_message = "The supplied single-NAT design must not be replaced by an unrequested architecture expansion."
  }
}

run "reject_unavailable_zone" {
  command = plan
  variables {
    availability_zones = {
      a = "eu-west-1a"
      b = "eu-west-1b"
      c = "eu-west-1d"
    }
  }
  expect_failures = [aws_vpc.hosting]
}

run "reject_empty_endpoint_policy" {
  command = plan
  variables {
    s3_endpoint_policy_json = "{}"
  }
  expect_failures = [var.s3_endpoint_policy_json]
}
