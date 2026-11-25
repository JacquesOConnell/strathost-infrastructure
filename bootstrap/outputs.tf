# Planning reference: ../TERRAFORM-IMPLEMENTATION-PLAN.md, sections 5 and 24.
# Return backend identifiers and policy assignments without credentials or state contents.

output "state_bucket_name" {
  description = "Versioned state bucket; not a workload export bucket."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_kms_key_arn" {
  description = "Customer-managed state encryption key ARN."
  value       = aws_kms_key.terraform_state.arn
}

output "backend_policy_arns" {
  description = "Policies to attach to existing roles through the identity-owning stack."
  value       = { for name, policy in aws_iam_policy.terraform_backend : name => policy.arn }
}

output "backend_role_assignments" {
  description = "Explicit role and policy mapping; this root does not alter existing role attachments."
  value = {
    for name, access in var.backend_access : name => {
      role_arn   = access.role_arn
      policy_arn = aws_iam_policy.terraform_backend[name].arn
      state_keys = access.state_keys
    }
  }
}

output "workload_backend_configuration" {
  description = "Non-secret backend settings shared by roots; each root supplies its exact state key."
  value = {
    bucket              = aws_s3_bucket.terraform_state.id
    region              = var.aws_region
    encrypt             = true
    kms_key_id          = aws_kms_key.terraform_state.arn
    use_lockfile        = true
    allowed_account_ids = [var.expected_account_id]
  }
}
