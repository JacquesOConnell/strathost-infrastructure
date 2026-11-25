terraform {
  required_version = ">= 1.17.2, < 2.0.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.18.0"
    }
  }
}
