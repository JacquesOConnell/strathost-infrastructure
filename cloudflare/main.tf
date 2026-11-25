# Separate state keeps optional edge administration and credentials out of AWS provisioning.
module "cloudflare" {
  source                        = "../modules/cloudflare"
  environment                   = var.environment
  account_id                    = var.account_id
  zone_id                       = var.zone_id
  public_hostname               = var.public_hostname
  secure_hostname               = var.secure_hostname
  public_origin_dns             = var.public_origin_dns
  secure_origin_dns             = var.secure_origin_dns
  approved_identity_provider_id = var.approved_identity_provider_id
  approved_emails               = var.approved_emails
  publish_dns                   = var.publish_dns
  origin_tests_verified         = var.origin_tests_verified
  zone_settings_verified        = var.zone_settings_verified
  manage_zone_settings          = var.manage_zone_settings
}
output "access_application_audience" { value = module.cloudflare.access_application_audience }
