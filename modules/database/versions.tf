# Plan section 3: use the same provider release family as the other modules.
terraform {
  required_version = ">= 1.17.2, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.73.0, < 7.0.0"
    }
  }
}
