mock_provider "cloudflare" {
  override_during = plan
}
variables {
  environment                   = "test"
  account_id                    = "00000000000000000000000000000001"
  zone_id                       = "00000000000000000000000000000002"
  public_hostname               = "www.example.com"
  secure_hostname               = "secure.example.com"
  public_origin_dns             = "fixture-public.eu-west-1.elb.amazonaws.com"
  secure_origin_dns             = "fixture-secure.eu-west-1.elb.amazonaws.com"
  approved_identity_provider_id = "00000000-0000-0000-0000-000000000003"
  approved_emails               = ["approved@example.com"]
}
run "access_before_dns_publication" {
  command = plan
  assert {
    condition = (
      length(cloudflare_dns_record.public_wordpress) == 0 && length(cloudflare_dns_record.secure_wordpress) == 0 &&
      cloudflare_zero_trust_access_policy.secure_users.decision == "allow" &&
      cloudflare_zero_trust_access_application.secure_wordpress.http_only_cookie_attribute &&
      length(cloudflare_zone_setting.strict_origin_tls) == 0
    )
    error_message = "Configure a narrow Access policy without publishing DNS or changing shared zone settings by default."
  }
}
run "reject_publication_without_origin_tests" {
  command = plan
  variables { publish_dns = true }
  expect_failures = [var.publish_dns]
}
