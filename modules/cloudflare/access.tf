# Plan 17: Access application first; public DNS is a separate activation step.
resource "cloudflare_zero_trust_access_policy" "secure_users" {
  account_id       = var.account_id
  name             = "strathost-${var.environment}-secure-users"
  decision         = "allow"
  session_duration = "8h"
  include = [for email in sort(tolist(var.approved_emails)) : {
    email = { email = email }
  }]
}
resource "cloudflare_zero_trust_access_application" "secure_wordpress" {
  account_id                 = var.account_id
  name                       = "strathost-${var.environment}-secure-wordpress"
  type                       = "self_hosted"
  domain                     = var.secure_hostname
  session_duration           = "8h"
  allowed_idps               = [var.approved_identity_provider_id]
  auto_redirect_to_identity  = true
  http_only_cookie_attribute = true
  policies = [{
    id         = cloudflare_zero_trust_access_policy.secure_users.id
    precedence = 1
  }]
}
