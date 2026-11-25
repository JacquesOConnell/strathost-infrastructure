# Non-secret inventory for the Checkmk configuration step.
output "host_inventory" {
  description = "Five Linux host entries plus the API-only AWS collector name."
  value = {
    site     = "strathost"
    region   = "eu-west-1"
    aws_host = "${local.resource_prefix}-aws"
    hosts = {
      "${local.resource_prefix}-docker-01" = var.private_ip_addresses["docker_01"]
      "${local.resource_prefix}-docker-02" = var.private_ip_addresses["docker_02"]
      "${local.resource_prefix}-docker-03" = var.private_ip_addresses["docker_03"]
      "${local.resource_prefix}-vpn"       = var.private_ip_addresses["vpn"]
      "${local.resource_prefix}-checkmk"   = "127.0.0.1"
    }
  }
}
