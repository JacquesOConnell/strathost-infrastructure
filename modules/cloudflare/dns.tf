# No internal/private or VPN proxied records. ACM validation records remain DNS-only and externally owned.
resource "cloudflare_dns_record" "public_wordpress" {
  count   = var.publish_dns ? 1 : 0
  zone_id = var.zone_id
  name    = var.public_hostname
  type    = "CNAME"
  content = var.public_origin_dns
  proxied = true
  ttl     = 1
  comment = "StratHost ${var.environment} public WordPress origin"
}
resource "cloudflare_dns_record" "secure_wordpress" {
  count      = var.publish_dns ? 1 : 0
  zone_id    = var.zone_id
  name       = var.secure_hostname
  type       = "CNAME"
  content    = var.secure_origin_dns
  proxied    = true
  ttl        = 1
  comment    = "StratHost ${var.environment} Access-protected WordPress origin"
  depends_on = [cloudflare_zero_trust_access_application.secure_wordpress]
}
# These settings affect the whole existing zone, so ownership is an explicit opt-in.
resource "cloudflare_zone_setting" "strict_origin_tls" {
  count      = var.manage_zone_settings ? 1 : 0
  zone_id    = var.zone_id
  setting_id = "ssl"
  value      = "strict"
}
resource "cloudflare_zone_setting" "minimum_tls" {
  count      = var.manage_zone_settings ? 1 : 0
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}
resource "cloudflare_zone_setting" "edge_https" {
  count      = var.manage_zone_settings ? 1 : 0
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = "on"
}
