# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5.
# Require an explicit account and external credentials before creating shared state storage.

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = local.required_tags
  }
}

data "aws_caller_identity" "deployment" {}
data "aws_partition" "current" {}
