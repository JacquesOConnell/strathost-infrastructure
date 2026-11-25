# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 7.1.
# Use regional S3 gateway routes without adding endpoint ENIs or security groups.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.hosting.id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.public.id],
    [for table in aws_route_table.application : table.id]
  )
  # DESIGN: the composition root supplies reviewed export/SSM paths; this is not IAM authorisation.
  policy = var.s3_endpoint_policy_json
  tags = merge(local.tags, {
    Name = "${local.resource_prefix}-vpce-s3"
  })
}
