# Deployment, configuration and acceptance

## 1. Current boundary

The source is implemented and locally checked. No StratHost AWS plan/apply, software installation, Cloudflare mutation, live notification or restore has been performed. These instructions describe future authorized deployment, not work already executed. Preserve the independent development Checkmk lab's account boundary.

The main repository root connects the small service modules for one selected environment. Use separate approved account sessions, tfvars and backend keys for each environment. Cloudflare has a separate root/state so edge credentials and DNS publication are independent. The original diagram and plans remain preserved; later decisions record scope refinements.

## 2. Prepare reviewed inputs

1. Confirm the target account, eu-west-1, physical AZ mapping, quotas and service availability. Check the selected Canonical AMIs, RDS MySQL 8.4.13/class/Multi-AZ combination and burstable CPU behaviour.
2. Obtain approval for estimated EC2, public IPv4, NAT, three ALBs, RDS Multi-AZ, EFS, KMS, storage, logs, backups and Cloudflare costs. No free-tier assumption applies.
3. Identify the applying role, key-administration roles and distinct recovery role. Confirm its least-privilege provisioning permissions and PassRole on the managed service roles. Existing operator/recovery trust is not modified by this source.
4. Supply issued eu-west-1 ACM certificate ARNs covering the three actual site names. Certificate issuance and DNS validation are externally owned inputs; do not import private keys into Terraform. Choose a private DNS suffix that will not unexpectedly shadow required public names. Obtain the separate trusted Checkmk HTTPS certificate/key through the approved process.
5. Review current Cloudflare origin IPv4 ranges against the versioned snapshot, exact VPN public-source CIDRs and client network overlap. Select approved names, IdP/MFA policy and explicit allowed users. Plan protected-origin JWT testing before publication.
6. Review SSM's required regional AWS artifact buckets for the selected update/patch features. Supply exact bucket ARNs to both the endpoint and runtime policies. Test them; restrictive endpoint policies can break updates when the needed artifacts are omitted.
7. Select approved OS/software package releases, base and built image digests, checksums and signing fingerprints. Record a release manifest including Docker, containerd, Compose, Buildx, EFS-utils provenance, AWS CLI, WordPress/PHP, Nginx, Checkmk Community and WireGuard. The example placeholders are deliberately not deployment values.
8. Approve RPO/RTO, retention, backup windows, scratch-space capacity, notification contacts and delivery method. Confirm Backup EC2/EFS service opt-in without overwriting unrelated regional settings.

## 3. Bootstrap remote state

Review `bootstrap/README.md`, supply its external same-account role inputs and exact authorized keys, and create the state bucket/key in its separate bootstrap workflow. Migrate bootstrap state only after verifying the bucket, encryption, versioning, state access and native lock behaviour. Keep local migration copies private until recovery is verified.

The examples authorize `environments/test/terraform.tfstate` and `cloudflare/test/terraform.tfstate` separately from the corresponding production keys. The IAM role owning each backend must match those keys. The bootstrap root is not the workload root.

## 4. Review the AWS plan

Copy `environments/test.tfvars.example` to an ignored local `.tfvars` file. Replace every placeholder and use a protected `backend.hcl` copied from the example. Keep the backend key/environment aligned. Run commands only after a separately authorized account/cost review:

```powershell
aws sts get-caller-identity
terraform init -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -var-file=environments/test.tfvars -out=output/strathost-test.tfplan
terraform show output/strathost-test.tfplan
# Apply only the exact reviewed plan once deployment is explicitly authorized.
terraform apply output/strathost-test.tfplan
```

Use Terraform 1.17.2 and the committed root lockfile. Saved plans may contain sensitive metadata and stay ignored/protected. Provider account allowlisting supplies an additional check; it is not a replacement for reading STS identity and reviewing the plan. Root key policies use account IAM delegation plus named administrators and scoped Logs service encryption; inspect real policy rendering and authorization before apply. `kms:*` on the account principal enables IAM delegation rather than granting every role key use.

The code graph creates roles and keys, networking/security/storage, database and EC2, target attachments, private DNS, monitoring permissions/diagnostic flow logs and backups. EC2 user data starts only the AMI's SSM agent. No application secret or registration credential enters user data. Whole-module dependencies wait for routing/security/storage setup; they do not establish service health.

All application forwarding is initially disabled. RDS deletion protection defaults on; production EC2/ALB protection is enabled. Keys and the backup vault have destruction guards. Do not run a general destroy expecting retained data to be automatically removed.

## 5. Configure servers and data

1. Verify SSM connectivity and identify the five instance IDs/private addresses from outputs.
2. Prepare approved packages/artifacts. Install the verified pinned AWS CLI where scripts need AWS calls. Never put static access keys in host credential files.
3. On Docker01/02/03, install Docker/EFS-utils using the [Docker runbook](../scripts/docker/README.md). Mount each site's access point and prove cross-AZ access before starting containers.
4. Populate the three site secret containers through an approved secret-management process, using independent site users/passwords/salts and consistent values across replicas. Store each host's protected site configuration and trusted RDS CA bundle.
5. Use a separately authorized, temporary administrator session to initialize the databases using the [WordPress runbook](../scripts/wordpress/README.md). The Docker instance role cannot retrieve the RDS master secret. Remove temporary administrator material afterwards.
6. Build/scan/publish the reviewed WordPress image, deploy each site on all three hosts and verify readiness/login/DB/EFS. Do not enable the ALB forwarding rules yet.
7. Generate/populate the VPN server key outside Terraform and configure approved public peer keys. Configure WireGuard and its private DNS forwarder using the [VPN runbook](../scripts/vpn/README.md). Test HTTPS access and denied database/other forwarding.
8. Prepare Checkmk's attached disk by volume ID, install the reviewed Community package, configure trusted HTTPS, register agents with TLS and discover services using the [Checkmk runbook](../scripts/checkmk/README.md).
9. On Docker01 only, enable WordPress cron and logical export timers. Check scratch space and completed export manifests. No atomic database/files consistency is claimed while writes continue.
10. Verify backup jobs and completed recovery points for all six selected resources, RDS automated backups, export retention, access logs and flow-log delivery.

## 6. Configure edge protection, then publish

Initialize the separate `cloudflare/` root with its own authorized backend key and narrowly scoped API token. Prepare Access using `publish_dns = false`, record the audience and configure the secure origin's exact issuer/audience. Existing zone TLS settings can remain externally owned; verify Full (strict), minimum TLS 1.2 and HTTPS redirect. Opt into Terraform ownership of zone-wide settings only after shared impact review.

Test the protected origin directly through an authorized controlled path with missing, forged, expired and wrong-audience tokens, and verify the valid-user path. Missing or unverified authentication must fail closed. IP allowlisting alone does not prove Cloudflare-zone identity. If custom origin mTLS is later selected, implement and test that separate proposal before asserting it is active.

Record health, host-routing and access evidence, enable only the corresponding AWS forwarding flags in a reviewed plan, and finally enable Cloudflare DNS publication. Public and secure CNAMEs point to different ALBs. Internal WordPress and Checkmk stay in private DNS. Retain WordPress login/role authorization even behind VPN/Access.

## 7. Acceptance evidence

| Area | Required live evidence |
|---|---|
| Account and cost | Approved identity, state isolation, regional availability/quotas and cost estimate |
| Network | Correct nine-subnet routes, no database Internet path, SSM and artifact access, logged accepted/rejected flows |
| Security | Denied SSH/DB/NFS/public Checkmk, correct source groups/CIDRs, no protected workload through the public host/port |
| Storage | TLS/IAM access-point mounts, cross-AZ upload access, denied unexpected roles and runtime export reads |
| Application | All nine targets healthy, real readiness, consistent sessions, login/role checks and actual secure JWT validation |
| Resilience | Drain/stop one Docker host; remaining hosts sustain tested demand; rehearse RDS failover and recovery |
| VPN/DNS | Approved peer handshake, trusted private HTTPS, no direct DB/general Internet routing, successful peer revocation |
| Monitoring | Five agent hosts, AWS API checks, Docker/VPN/EFS checks, synthetic HTTPS/TLS, failed-job/freshness alerts, real notification delivery |
| Backups | Successful jobs/recovery points, export checksum verification and a rehearsed EC2/EFS/RDS/Checkmk/application restore |
| Operations | Reboot ordering, certificate/secret rotation, resource saturation, CPU credits, clean rollback and approved teardown procedure |

For HTTPS synthetics use a real application path and expected status/content; the diagnostic `/healthz` is intentionally unavailable on named external vhosts. Protected synthetic checks require an explicitly approved test identity or method; do not reuse personal credentials. Checkmk self-monitoring cannot notify during complete instance failure.

Record timestamps, configuration/image identifiers, expected versus actual results and remaining gaps. Passing local mocks is not deployment acceptance. No resource is operational merely because Terraform created it.

## 8. Changes, recovery and teardown

Drain and update one fixed Docker host at a time, retaining two tested healthy hosts. Rehearse database/plugin migration compatibility and restore before changes that cannot be reversed by an image rollback. VPN and Checkmk are accepted single-instance dependencies; Docker01 also owns scheduled jobs until deliberately reassigned.

For teardown, first verify retained exports/recovery points, key retention, account authorization and costs that survive compute removal. Disable public publication and stop scheduled writes through the approved change process. Export and securely retain the required configuration/recovery identifiers. Keys and the vault deliberately block general destruction; preserve them in an approved retained-resource state or make separately reviewed guard changes only after recovery requirements are resolved. Never use forced detachment, blanket bucket emptying or unreviewed key deletion to make destroy pass.

References: [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3), [SSM artifacts](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-technical-details.html), [KMS delegation](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html), [AWS Backup encryption](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html), [Cloudflare JWT validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/).
