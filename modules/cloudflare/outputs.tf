output "access_application_audience" {
  description = "Non-secret audience to supply to the secure site's origin JWT validator."
  value       = cloudflare_zero_trust_access_application.secure_wordpress.aud
}
output "access_application_id" {
  value = cloudflare_zero_trust_access_application.secure_wordpress.id
}
