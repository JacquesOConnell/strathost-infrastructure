terraform {
  required_version = "= 1.17.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.73.0"
    }
  }
  # Supply an environment-specific key and approved bootstrap settings at init.
  backend "s3" {}
}
