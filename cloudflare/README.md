# Separate edge deployment root

This root calls the [Cloudflare service module](../modules/cloudflare/README.md). It uses a different state key from the AWS workload and gets its token only from `CLOUDFLARE_API_TOKEN`. Its default configuration prepares Access without publishing records or taking ownership of shared zone settings.

Copy the backend and variable examples to ignored local files, replace every placeholder and verify the approved account/zone. Use the AWS root's ALB DNS outputs; do not pass its complete state file or any credentials. The state bucket's backend policy must include the exact Cloudflare environment key. Follow [deployment order](../docs/DEPLOYMENT.md) before any plan/apply or DNS activation.

Local provider schema validation passes with Cloudflare 5.18.0. The module has two passing mocked plan tests; no live Cloudflare changes were made.
