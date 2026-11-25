# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 24.
# Return identifiers; the composition root orders server bootstrap after network configuration.

output "vpc_id" {
  description = "Dedicated VPC ID."
  value       = aws_vpc.hosting.id
}

output "vpc_cidr_block" {
  description = "Diagram-preserved IPv4 address space."
  value       = aws_vpc.hosting.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs by stable a/b/c slot."
  value       = { for zone, subnet in aws_subnet.public : zone => subnet.id }
}

output "application_subnet_ids" {
  description = "Private application subnet IDs by stable a/b/c slot."
  value       = { for zone, subnet in aws_subnet.application : zone => subnet.id }
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs by stable a/b/c slot."
  value       = { for zone, subnet in aws_subnet.database : zone => subnet.id }
}

output "subnet_cidrs" {
  description = "Public, application and database CIDRs by slot, for fixed-address allocation."
  value       = local.subnet_cidrs
}

output "availability_zones" {
  description = "Approved account-relative AZ names."
  value       = var.availability_zones
}

output "application_route_table_ids" {
  description = "Application route table IDs by stable slot."
  value       = { for zone, table in aws_route_table.application : zone => table.id }
}

output "nat_gateway_ids" {
  description = "Zonal NAT IDs keyed by hosting slot; c only for the single-NAT profile."
  value       = { for zone, gateway in aws_nat_gateway.application_egress : zone => gateway.id }
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint ID; endpoint policy does not replace IAM permissions."
  value       = aws_vpc_endpoint.s3.id
}

output "s3_prefix_list_id" {
  description = "AWS S3 managed prefix list for later security-group egress rules."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

# Plan 6.1: expose the actual physical zone mapping for the pre-deployment review.
output "availability_zone_ids" {
  description = "Account AZ name-to-ID mapping for the pre-deployment review."
  value = zipmap(
    data.aws_availability_zones.available.names,
    data.aws_availability_zones.available.zone_ids
  )
}
