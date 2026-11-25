# Cloudflare edge configuration

I kept the optional edge deployment in a separate `cloudflare/` root and state. The AWS root needs no Cloudflare token and does not publish DNS. Provider 5.18.0 is explicitly pinned and signed by its publisher; upgrade it through reviewed schema/behaviour checks.

The module defines a reusable Access allow policy containing only approved email addresses, one existing MFA-capable IdP and a self-hosted secure application with an eight-hour session. The application audience is output for the origin JWT validator. Publication creates proxied public/secure CNAMEs pointing at their distinct ALBs. It stays disabled until recorded origin and strict-TLS checks are attested. No internal/private or proxied VPN records are created.

Zone-wide Full (strict), minimum TLS 1.2 and HTTPS redirect settings are explicit opt-in because a zone can contain unrelated applications. If externally owned, verify them rather than taking Terraform ownership. Request only the API token permissions needed for the approved zone's DNS and the account's Access configuration; include Zone Settings Write only when authorized to manage those settings. Credentials come from `CLOUDFLARE_API_TOKEN`, never state inputs. Existing IdP, account/zone and certificate-validation records are not adopted automatically.

The Access edge policy does not alone secure direct origin access. The secure WordPress image validates signature, issuer, audience and token time claims independently. Configure the correct audience/issuer, test missing/forged/expired/wrong-audience tokens and direct-origin bypasses before enabling routing or publishing DNS. Origin mTLS is optional, not silently required by an environment label.

Schema validation and two mocked tests pass; no Cloudflare API mutations or authenticated tests have run. Source schemas were checked against the provider's versioned official resource documentation.

References: [provider 5.18 Access application](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.18.0/docs/resources/zero_trust_access_application.md), [Access policy](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.18.0/docs/resources/zero_trust_access_policy.md), [DNS record](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.18.0/docs/resources/dns_record.md), [token validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/).
