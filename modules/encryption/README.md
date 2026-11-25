# Workload encryption keys

I used seven separate customer-managed KMS keys for `ebs`, `rds`, `efs`, `backup`, `exports`, `secrets` and `logs`, refining section 9 of the [technical plan](../../TERRAFORM-IMPLEMENTATION-PLAN.md). The unused SNS alerts key was removed following the Checkmk-only monitoring decision. State encryption remains in the bootstrap root. Schema validation and two mocked test runs pass with AWS provider 6.73.0; live cryptographic and service-integration tests have not run.

## What I used and why

Each key is symmetric, regional and used for encryption/decryption, with automatic rotation enabled, a thirty-day deletion window and an alias `alias/strathost/{environment}/{purpose}`. Separate keys let recovery, retention and service access be reviewed independently. Outputs contain identifiers only; no key material is generated or exported.

I set `prevent_destroy = true` for every workload key. This also protects non-production keys because retained snapshots or backups may still depend on them. Approved teardown requires a deliberate review of retained data and a reviewed configuration change before scheduling deletion. The thirty-day deletion delay is not a substitute for retaining a key through the full recovery period.

## Policy ownership and required composition

Each key and alias has a direct Terraform name, such as `aws_kms_key.efs` and `aws_kms_alias.efs`. The module takes a simple `key_policy_json` map containing the seven complete policies and passes each policy directly to its named key. There is no key-resource generator or extra policy-normalization layer.

The root encryption.tf supplies account IAM delegation, explicit same-account key administrators and a regional Logs service grant restricted by encryption context. Root iam.tf supplies named-key workload permissions. Account delegation follows AWS's documented policy model: IAM grants are still required, and identity policies must be reviewed alongside key policies. The applying role must remain able to manage the keys. Existing recovery roles need separately reviewed restore permissions.

Required checks include CloudWatch Logs' regional service principal and encryption context, RDS/Secrets Manager grants, backup recovery access and S3 Bucket Key encryption contexts. Grant operations and service conditions must match the actual integration. Do not apply one generic source-ARN condition to services that do not provide that context.

Input validation confirms the seven purpose keys and non-empty IAM JSON structure. It does not evaluate effective authorization or prove lockout safety. The mock fixture is not the composition root's complete service policy; passing it does not prove effective authorization. The two tests check key configuration and rejection of empty documents, not cryptographic access.

ALB access logs and public origin-trust artifacts intentionally use SSE-S3 in storage. Applying a blanket SSE-KMS requirement there would conflict with the selected ALB log delivery configuration. Source-encrypted EBS recovery points may retain the EBS key even when AWS Backup also has a vault key; both must survive the retention period.

References: [KMS policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html), [CloudWatch Logs encryption](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html), [Backup encryption](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html), [Terraform KMS key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key).
