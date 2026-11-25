# Public records are managed by the separate Cloudflare root; never publish private addresses there.
module "dns" {
  source                = "./modules/dns"
  environment           = var.environment
  cost_center           = var.cost_center
  vpc_id                = module.networking.vpc_id
  private_zone_name     = var.private_dns_zone_name
  internal_hostname     = var.hostnames.internal
  checkmk_hostname      = var.checkmk_hostname
  internal_alb_dns_name = module.load_balancing.dns_names.internal
  internal_alb_zone_id  = module.load_balancing.zone_ids.internal
  checkmk_private_ip    = module.ec2.private_ip_addresses.checkmk
}
