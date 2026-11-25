# Workload storage

I grouped S3 and EFS under storage, with their resource definitions in separate files. This implements sections 11 and 12 of the [technical plan](../../TERRAFORM-IMPLEMENTATION-PLAN.md). Schema validation and four mocked test runs pass with AWS provider 6.73.0; no data has been created, mounted, backed up or restored in AWS.

## S3 settings and reasons

| Bucket | Encryption and retention | Reason |
|---|---|---|
| Application exports | Exports KMS key, Bucket Keys, versioning; 30 days production or two days non-production for current/noncurrent objects | Separates application-generated backups from state and service recovery points |
| ALB access logs | SSE-S3 and versioning; 90 days production or 14 days non-production | Meets the selected ALB access-log delivery encryption requirements |
| Origin trust | Optional custom origin mTLS proposal; SSE-S3 and versioning; no current-object expiration, noncurrent versions retained 365 days | Preserves the public CA bundle and its rotation history for origin mTLS |

All buckets disable force destruction, enforce BucketOwnerEnforced ownership and block public ACLs/policies. Lifecycle rules abort incomplete multipart uploads after seven days and clean expired delete markers separately. Retention is an engineering selection from the plan, not a measured regulatory requirement. The optional standalone CloudTrail bucket belongs to the later monitoring/audit stage and is not included here.

Client requests must use TLS. The bucket policy exempts direct AWS service principals from this transport deny where their request context can differ; this does not grant them access. The ALB log policy grants only the documented delivery principal and three account-specific log paths.

The shared Docker runtime role can upload exports to `sites/{site_key}/daily/` and list those prefixes. All three Docker hosts share that role, so permission does not isolate Docker01; the later configuration will schedule exports only on Docker01. Runtime IAM and endpoint policies must preserve the same prefix restrictions. Bucket policy allow statements are not a universal permission boundary for other identity policies, so authorization tests remain required.

Export object reads are explicitly denied outside the distinct recovery role, and unexpected principals cannot write exports. The recovery role also needs KMS Decrypt and matching IAM permissions. Runtime roles receive no export read/delete grant here. Explicit conflicting KMS/algorithm headers and customer-provided encryption keys are denied; omitted headers can use the correct bucket defaults.

## EFS settings and reasons

I used one encrypted Regional filesystem, not three filesystems. It uses the EFS KMS key, general-purpose performance, elastic throughput, IA after thirty days and return to the primary class on first access. Those throughput/lifecycle choices follow the technical plan and require workload cost/performance measurement before production acceptance.

Three mount targets occupy application A/B/C at `10.0.4.20`, `10.0.5.20` and `10.0.6.20`, with only the dedicated EFS security group. Each declared site has its own access point at `/sites/{site_key}`, permissions `0750`, and an explicit stable POSIX UID/GID. Default demonstration sites use IDs 10001, 10002 and 10003; IDs never depend on sorted map position.

The filesystem policy requires the Docker role, TLS, a managed mount target and an approved site access point. It denies ClientRootAccess and unexpected client roles. These are client permissions, not control-plane backup/restore permissions. The shared Docker role can access all configured site access points; this is not strong isolation between hostile tenants on shared hosts.

I disabled EFS's separate automatic backup plan to avoid duplicate schedules. The explicit AWS Backup module selects EFS and all five EC2 servers. This is configured coverage, not proof of completed jobs or recoverable data; the `efs-daily` tag is metadata only. WordPress should store mutable uploads on EFS and use immutable images for core/plugins/themes. Host scripts must verify successful mounts before starting containers.

## Inputs and outputs

Inputs include the approved account/environment, cost center, `efs_kms_key_arn`, `exports_kms_key_arn`, application subnet IDs, EFS security group, and Docker/recovery role ARNs. `site_posix_ids` is a simple map such as `public_wordpress = 10001`; it replaces nested site objects. Origin trust requires an existing reviewed public CA PEM file; validation rejects missing certificate markers or private-key content. This is a content check, not cryptographic CA validation. Trust-store validation and an actual mTLS handshake remain later acceptance steps.

Each bucket, encryption configuration and lifecycle rule is explicitly named, for example `aws_s3_bucket.workload_exports`. Only repeated privacy, ownership and versioning settings share a straightforward `for_each` across bucket IDs. There are no dynamic lifecycle blocks.

Outputs expose bucket names/ARNs, site export prefixes, EFS metadata and the public CA object's key/version when enabled. They return identifiers only. The composition root must order application/load-balancer setup after storage policies, encryption and mount targets are configured. No secret values are output. S3 public access blocks also apply to the trust bucket; the public CA need not be publicly downloadable.

## Tests and remaining verification

Four mocked plan runs cover bucket privacy, distinct encryption choices, Regional EFS topology, stable site paths/IDs, disabled duplicate backup plan, duplicate POSIX rejection, separation of recovery/runtime identities and optional diagram-baseline origin trust. Policy-document results are mocked; these tests do not validate rendered IAM policy semantics or AWS authorization.

Before deployment, render and inspect the real policies, confirm account/region/subnets and key grants, validate the public CA bundle, verify the explicit backup plans and jobs, and test ALB log delivery, TLS/IAM mounts, cross-AZ file access, export writes and denied reads, and successful recovery. A versioned S3 bucket and an EFS tag alone are not application-consistent backups.

References: [ALB log delivery](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html), [S3 policy conditions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html), [S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html), [EFS IAM policies](https://docs.aws.amazon.com/efs/latest/ug/security_iam_resource-based-policy-examples.html), [EFS access points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html), [EFS automatic backups](https://docs.aws.amazon.com/efs/latest/ug/automatic-backups.html).
