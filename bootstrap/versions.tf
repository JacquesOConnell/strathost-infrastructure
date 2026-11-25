# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 3.1 and 5.
# Pin the bootstrap toolchain so state resources use the reviewed provider schema.

terraform {
  required_version = "= 1.17.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.73.0"
    }
  }
}
