# StratHost implementation record

## 1. Scope and evidence

I implemented the supplied architecture with small service modules, descriptive resources and separate server scripts. This record explains what I used and why, rather than paraphrasing the code. The source diagram, master plan and technical plan remain unchanged. The independent development-account Checkmk trial is separate.

As of 25 November 2026, source configuration and local checks are complete for the current baseline. No StratHost live plan/apply, installation, Cloudflare mutation, notification, backup or restore has run. Deployment inputs and live acceptance remain necessary; local results do not establish production readiness.

## 2. State and module structure

I started with a separate bootstrap root because the workload cannot use an S3 backend before its bucket exists. It defines private versioned state storage, a rotating KMS key, native S3 locking, exact per-role state/lock keys and retention of noncurrent state versions. Deletion is permitted for lock objects, not state objects. Existing backend/key-admin identities are external inputs rather than adopted IAM identities.

The repository root now connects the service modules directly. Test and production use separate tfvars/backend inputs instead of duplicating all module calls or introducing a platform wrapper. Cloudflare has its own root/state because Access/DNS ownership and credentials are separate from AWS provisioning. Generated root lockfiles pin the tested providers.

I kept named security groups, keys, buckets, EC2 hosts, ALBs and target groups. Small loops remain for naturally repeated subnet slots, CIDRs, access points, target attachments and shared bucket controls. The code comments reference plan sections and identify important engineering choices; the service READMEs hold the fuller rationale.

## 3. Networking and traffic boundaries

I preserved VPC 10.0.0.0/16 and the nine supplied /24 subnets across three AZ slots. One IGW is attached to the VPC. The baseline has one zonal NAT in public C, shared by application route tables. Per-AZ NAT remains an optional recommendation, not a requirement triggered by the production label. The database route table has no Internet/NAT/VPN/S3 endpoint routes.

Every subnet has an explicit route-table association. The unused default security group and main route table are quarantined. I retained the selected permissive IPv4 NACL and use dedicated stateful security groups for workload enforcement. The S3 gateway endpoint serves public/application tables with an identity/path-limited policy composed at the root. Approved SSM artifact reads are explicit inputs.

Eight dedicated security groups separate three ALBs, Docker, MySQL, EFS, VPN and Checkmk. ALBs reach different Docker proxy ports 8080/8081/8082. MySQL/NFS accept only Docker; Checkmk agent traffic and registration have their own rules. VPN traffic uses controlled SNAT from 10.0.1.10, and UDP 51820 requires approved public client ranges. No inbound SSH, public Checkmk UI, public MySQL or public NFS is configured. Broad TCP 443 egress on managed hosts remains a documented package/API exception from the plan.

## 4. IAM, secrets and encryption

I used separate Docker, VPN, Checkmk and AWS Backup roles. Only the three machine roles receive instance profiles and the SSM core managed policy. AWS Backup uses its managed service backup policy as an explicit multi-service exception. Runtime grants reference exact site secrets, EFS access points, S3 export prefixes, approved artifacts and named encryption keys. Existing recovery/operator roles remain externally owned.

The seven workload KMS keys separate EBS, RDS, EFS, Backup, exports, secrets and logs. I removed the unused SNS alerts key after selecting Checkmk-only monitoring. Keys rotate and use thirty-day deletion delays plus destruction protection. Root key policies enable account IAM delegation, named administrators and the Logs service restricted to the exact diagnostic log contexts. Identity policies supply the actual resource grants; mock tests do not establish effective authorization.

Terraform creates site/VPN secret containers without values. RDS generates/manages its administrator secret and exposes only the ARN. The Docker runtime role cannot retrieve the administrator secret. Site credentials and shared salts are populated outside Terraform and read at runtime into protected files; passwords/private keys never appear in Terraform variables, user data or state values. The recovery-role owner receives a proposed export-read policy for separate review, not automatic restore authority.

## 5. Storage and database

I separated KMS-encrypted application exports, compatible SSE-S3 ALB access logs and an optional public CA artifact bucket for the separate origin-mTLS proposal. Buckets block public access, enforce ownership, use versioning and refuse force destruction. Export writers and recovery readers are separate; runtime object reads are explicitly denied. Retention differs by environment and is a selected operational policy, not a measured regulatory requirement.

One encrypted Regional EFS filesystem has three application-subnet mount targets and stable per-site POSIX access points. The filesystem policy requires the Docker role, TLS, a mount target and an approved access point while denying client root access. All Docker hosts share each site's uploads; WordPress core/plugins/themes are released through reviewed images. The shared machine identity and privileged Docker daemon remain trust boundaries, not strong hostile-tenant isolation.

RDS uses one private encrypted MySQL deployment with AWS-managed primary/standby, a three-subnet group, TLS-required parameters and an RDS-managed administrator secret. Multi-AZ remains enabled in test as well as production to preserve the supplied primary/standby design. Production uses db.t4g.medium/100 GiB and test db.t4g.micro/20 GiB with storage ceilings. These are initial sizing selections requiring measured testing. Native backups, bounded diagnostics, maintenance windows, deletion protection and an explicit final-snapshot label support operations and recovery.

## 6. Compute, load balancing and DNS

I used three fixed Docker instances in application A/B/C, a single VPN in public A and a single Checkmk in public C. Pinned Canonical Ubuntu 24.04 AMD64 AMIs are checked through owner/family/architecture filters. All hosts require IMDSv2, encrypted gp3 root disks and role-based SSM administration. Standard CPU credits bound burst-surplus costs but may throttle exhausted hosts; proposed sizes need capacity tests.

VPN receives an EIP and disables source/destination checks for its forwarding role. Checkmk receives a separate encrypted data disk and an intentional public IPv4 for outbound access in the diagram's public subnet. Dashboard access remains private through security groups. Its fixed 10.0.3.30 address is an engineering allocation, not a value specified in the diagram. Private Checkmk placement remains a recommendation.

Three independent ALBs span three subnets each and register all three Docker hosts in their separate target groups. Listeners require issued ACM certificates, deny by default and activate hostname rules only after reviewed tests. Secure-origin activation additionally records authentication-test verification; the application validator, not the flag, enforces authentication. Private backend HTTP is an explicit design choice, not end-to-end TLS. Health checks require exactly HTTP 200 from real application readiness.

A private Route 53 zone supplies internal WordPress and Checkmk names through the VPC/VPN resolver path. Public/secure DNS is managed separately by Cloudflare. Existing issued certificate ARNs and approved private/public names remain owner inputs; certificate private keys are not imported into Terraform.

## 7. Server configuration

The Docker script installs explicitly selected official repository versions and an approved EFS-utils artifact, bounds logs and avoids remote Docker API access. EFS mounts use TLS/IAM/access points and refuse local fallback. Each site's Compose project has a dedicated proxy port, shared database/uploads/salts and no published WordPress container port.

The WordPress image includes explicit RDS CA verification and protected-origin JWT validation. Site initialization uses a separate temporary administrator credential and creates site-only grants for the three fixed host addresses. Deployment reads only site secrets at runtime, refreshes image-derived core files and uses mount-dependent systemd units. Docker01 alone schedules cron and daily logical exports; exports include checksums and a final manifest but do not claim atomic database/files consistency during writes.

WireGuard retrieves its server key at runtime, validates approved peer public keys/tunnel /32s, restricts forwarding to private HTTPS and uses dedicated firewall chains with controlled SNAT. Its DNS listener is tunnel-only. Checkmk scripts verify the Community package/signature, prepare the dedicated disk by volume ID, create the site, configure trusted HTTPS and register TLS pull agents without command-line passwords. Restored data is never silently initialized over.

A subsequent local Docker Linux run built the WordPress image and passed PHP lint plus 32 application checks using disposable TLS/database/issuer/storage fixtures. It exercised the actual PHP drop-ins, Compose file and production proxy template. Secrets Manager access, real RDS/EFS and Ubuntu/systemd installers remain untested; local fixtures are not EC2 installation evidence. The runbooks describe prerequisites, ordering, rollback and remaining acceptance.

## 8. Monitoring and recovery

Checkmk is the monitoring platform. The instance role reads native AWS metric/inventory APIs; Linux agents supply host checks. Separate local checks cover EFS mount presence, completed backup-point freshness and latest job failure/partial state. Billing/classic-ELB/service-limit collection is disabled. I reviewed the selected non-limit API calls against the official v2.5.0p21 plugin source; live permission verification remains required and broad read-only access is not silently granted.

No parallel CloudWatch alarms, dashboards, agents or SNS topics are created. Encrypted RDS diagnostic logs and VPC Flow Logs support investigation, with bounded retention and dedicated delivery permissions. Notifications, synthetic protected-user checks, Docker plugin installation and successful end-to-end polling require site configuration and live tests. A single Checkmk instance cannot notify during its own total loss.

AWS Backup explicitly selects all five EC2 instances and Regional EFS daily, with protected vault/key retention. EC2 selection includes Checkmk's attached data disk after attachment. RDS uses its native automated backups, and Docker01 supplies separate logical S3 exports. EFS recovery points use the vault key while EBS snapshots retain source-key dependencies. No successful job or restore is claimed.

## 9. Validation and remaining acceptance

All fifteen Terraform roots/module directories validate. All 31 mocked Terraform runs and five backup-check Python tests pass. Bash/Python syntax and Compose configuration also pass. The root composition test needed explicit plan-time mock IDs/ARNs because unknown set members prevented cardinality assertions; this was fixed in fixtures rather than changing deployment behaviour.

Docker Desktop was subsequently started and the application image built successfully. All 32 local integration checks passed, with PHP 8.3.37 and WordPress 7.1.5 on Debian 13 containers. TLS mismatch/untrusted-CA failures, invalid Access tokens, WordPress login boundaries, replica sessions and readiness failure/recovery were verified. Test containers/networks/volumes were removed and cleanup independently checked. No Ubuntu installation, systemd run, real AWS permission evaluation, VPC packet test, Cloudflare account test or restore was performed. Mocked IAM documents do not prove effective policy permissions. Detailed evidence is recorded in [validation](validation/2026-11-25.md).

The [deployment runbook](DEPLOYMENT.md) lists remaining owner inputs, controlled plan/apply, configuration order and acceptance evidence. [Recommendations](RECOMMENDATIONS.md) separately cover automatic replacement, per-AZ egress, private Checkmk placement, tested N-1 capacity and recovery improvements. These are not silently deployed extras.
