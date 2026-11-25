# Planning reference: ../../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 3.1.
# Keep S3 and EFS schemas within the tested AWS provider family.

terraform {
  required_version = ">= 1.17.2, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.73.0, < 7.0.0"
    }
  }
}
