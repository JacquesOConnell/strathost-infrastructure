terraform {
  required_version = "= 1.17.2"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.18.0"
    }
  }
  backend "s3" {}
}
# Read CLOUDFLARE_API_TOKEN from the operator's environment, never tfvars.
provider "cloudflare" {}
