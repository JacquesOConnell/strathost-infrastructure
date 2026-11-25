# StratHost Terraform Implementation Plan

**Document status:** Complete pre-development specification; proposed configuration, not deployed infrastructure.  
**Prepared:** 24 November 2026.  
**Repository:** `JacquesOConnell/strathost-infrastructure`.  
**Primary region:** `eu-west-1` (Ireland).  
**Authoritative inputs:** [architecture diagram](strathost-infrastructure.png) and [existing master plan](STRATHOST-MASTER-PLAN.md).  
**Implementation boundary:** Produce this specification before creating Terraform, cloud-init, application configuration or cloud resources. No such implementation is included in this change.

**Navigation:** [Scope and decisions](#1-purpose-interpretation-and-readiness) · [Implementation order](#2-implementation-sequence-and-module-contracts) · [Network](#6-vpc-addressing-and-subnet-provisioning) · [Security](#8-security-groups-and-traffic-contracts) · [Data services](#11-s3-workload-log-and-origin-trust-buckets) · [Compute](#14-ec2-operating-system-sizing-and-ebs) · [Traffic and TLS](#15-certificates-origin-trust-and-private-dns-prerequisites) · [Operations](#18-wireguard-vpn-configuration-contract) · [Inventory](#22-consolidated-resource-inventory-and-count-reconciliation) · [Variables](#23-typed-variable-catalogue-and-validation-rules) · [Outputs](#24-output-catalogue-and-downstream-handoff) · [Testing](#25-verification-specification-and-acceptance-evidence) · [Deployment](#26-deployment-change-rollback-costs-and-teardown) · [References](#28-official-reference-index-and-maintenance-notes).

## 1. Purpose, interpretation and readiness

This document specifies the resource graph, configuration contracts and operational acceptance criteria for the three-Availability-Zone StratHost WordPress hosting platform. A developer should be able to implement the modules in the order below without inventing networking, exposure, encryption, storage or resource ownership decisions.

The diagram defines topology, not every implementation setting. Use the following provenance labels throughout:

| Label | Meaning |
|---|---|
| **ARCH** | Explicitly depicted in the supplied architecture diagram. |
| **MASTER** | Decision or requirement already documented in the master plan. |
| **DESIGN** | Selected engineering proposal added by this specification; requires review as a design decision, not attribution to the original architecture. |
| **INPUT** | Account, domain, identity, licence or business value that the owner must supply. Its absence blocks the affected deployment, not writing the corresponding module. |
| **OPTION** | Explicit extension excluded from the baseline unless enabled and costed. |

All numerical sizing, schedules, alarm thresholds and recovery objectives below are **DESIGN** planning values unless identified otherwise. They are not measured workload requirements. Production means a configuration profile with production controls; it does not mean this repository has been deployed or proven production-ready.

Official documentation was consulted during specification preparation. Links are grouped beside each subsystem and indexed in section 28. Resource argument lists below select the settings that must be explicit; omitted service/provider arguments retain the pinned provider's defaults only where this document says so. Verify the generated plan and provider schema before implementation approval. AWS regional availability, quotas, AMI IDs and commercial product entitlements require account-specific checks.

### 1.1 Source-to-design traceability

| ID | Original requirement / prior decision | Selected implementation and provenance |
|---|---|---|
| A01 | ARCH: VPC `10.0.0.0/16`; nine illustrated `/24` subnets | Preserve all CIDRs and three network tiers. |
| A02 | ARCH: datacentres labelled west1 a/b/c | MASTER: use `eu-west-1`; resolve account-specific AZ names/IDs. Region is an interpretation, not a literal diagram label. |
| A03 | ARCH: IGW drawn in B; NAT drawn near C | MASTER: one VPC IGW; one **zonal** public NAT in C for test; three zonal public NATs for production. Do not substitute a Regional NAT implementation silently. |
| A04 | ARCH: public, secure and internal load balancers shown separately | MASTER: three independent ALBs, each covering three subnets. They do not forward to one another. |
| A05 | ARCH: Docker01, Docker02, Docker03 | MASTER: three fixed EC2 hosts, one per app subnet; no ASG, ECS, EKS or container scheduler assumed. |
| A06 | ARCH: VPN in public A | MASTER/DESIGN: WireGuard EC2 with EIP, UDP 51820 and controlled SNAT. |
| A07 | ARCH: Checkmk in public C | MASTER preferred correction: app C at `10.0.6.30`, no public address, NAT egress. Public-C placement is not selected. |
| A08 | ARCH: WordPress EFS symbol in each app subnet | MASTER: one Regional EFS filesystem; three mount targets. DESIGN: per-site access points. |
| A09 | ARCH: MySQL primary A, standby B | MASTER: one RDS MySQL Multi-AZ DB instance deployment with AWS-managed standby placement; no second `aws_db_instance` and no read replica. |
| A10 | ARCH: backup S3 drawn in A | MASTER: regional workload-export bucket, outside subnet topology; additional buckets serve Terraform state, ALB logs and origin trust. |
| A11 | ARCH: Cloudflare at entry | MASTER: optional integration until domain/credentials exist. DESIGN: Full (strict), dedicated origin mTLS and Access JWT validation for protected sites. |
| A12 | MASTER: Ubuntu 24.04, SSM, encrypted gp3, private RDS, backups and scoped IAM | Preserve and specify arguments below. |
| D01 | MASTER: backend 8080 proposed for all ALBs | DESIGN refinement: distinct host proxy ports 8080 public, 8081 secure, 8082 internal. This closes a common protected-workload routing bypass. |
| D02 | MASTER: keep default NACLs initially | Adopt the new VPC's default NACL with explicit allow-all IPv4 rules; SGs are the enforcement boundary. Custom tier NACLs are excluded initially. |
| D03 | MASTER: authentication for secure websites unresolved | Select Cloudflare Access plus origin JWT verification; mTLS authenticates the Cloudflare origin connection, not the end user. |
| D04 | MASTER: VPN routed or SNAT mode unresolved | Select SNAT only for approved private destinations; no VPN CIDR return routes and no database forwarding. |
| D05 | MASTER: RPO/RTO unconfirmed | Select provisional targets in section 20; retain owner sign-off and restore evidence as production gates. |

### 1.2 Explicit exclusions and availability limits

The baseline does not include a domain purchase, hosted mail, production customer migration, public SSH, a bastion, RDS Proxy, read replicas, Kubernetes, autoscaling, managed Client VPN, WAF, cross-region recovery or a CI apply pipeline that runs automatically. Cloudflare and AWS accounts remain separately administered. The existing diagram and master plan must remain in the repository unchanged as source evidence.

The VPN and Checkmk servers are single-instance dependencies. Test's single NAT is also an AZ dependency. Multi-AZ ALBs, EFS and RDS do not make the whole platform failure-free. The fixed Docker fleet needs explicit replica placement, release coordination and sufficient capacity after one host fails.

## 2. Implementation sequence and module contracts

Use one workload state per environment and a separate bootstrap state. Compose child modules through `modules/platform`; expose environment overrides through `environments/dev`, `environments/test` and `environments/prod`. Keep provider configurations and credentials in roots. Do not create a separate state for every module.

| Stage | Module / ownership | Inputs from prior stages | Required outputs / completion condition |
|---|---|---|---|
| 0 | Design/release manifest | Owner inputs, this specification | Accepted decisions; tool, OS and package release manifest. |
| 1 | `bootstrap` | Account ID, region, administrator principal | State bucket, state KMS key, scoped backend permissions; state migration verified. |
| 2 | Root composition / locals | Environment configuration | Validated naming, tags, AZ map and profiles. |
| 3 | `networking` | CIDRs, AZ map, NAT profile | VPC, nine subnets, routes, endpoint, default controls. |
| 4 | `kms`, SG shells, IAM role shells | Account/region, VPC, deterministic resource names | Encryption keys, SG IDs, role ARNs. |
| 5 | `s3`, log groups | Keys, principals | Export/log/trust buckets, policies and log group ARNs. |
| 6 | `efs`, `database` | Subnets, SGs, keys, monitoring role | EFS/access points, RDS endpoint and managed-secret ARN. |
| 7 | IAM permissions and SG rules | Storage ARNs, role IDs, SG IDs | Runtime policies and standalone SG rules; no dependency cycles. |
| 8 | `compute` | All runtime dependencies, AMI manifest | Five EC2 instances, EIP association, optional Checkmk data volume. |
| 9 | Certificate/DNS and `load-balancing` | Domain, validated certs, hosts, buckets | Three ALBs, listeners, rules, target groups and registrations. |
| 10 | `cloudflare`, private DNS | ALB DNS, approved domain/zone | Public DNS, Access policy, internal DNS; external AOP handoff verified. |
| 11 | `backup`, `monitoring` | Resource IDs, logs, SNS destination | Backup schedules, alarms, events, audit integration and budget. |
| 12 | Configuration management | Non-secret infrastructure outputs | OS/runtime, mounts, WordPress, WireGuard and Checkmk configured. |
| 13 | Verification and handover | Approved reviewed plan, optional sandbox | Static evidence, optional live evidence, rollback/teardown record. |

Stages are a logical dependency order, not instructions to use routine `terraform -target`. Terraform must build one complete workload graph. Create roles and SG shells before cross-referencing policies/rules. Avoid making compute depend on ALB listeners: target attachments depend on compute, not vice versa. Cloudflare Access audience is delivered to the host configuration workflow after application creation; it is not an EC2 creation dependency.

Recommended files within each child module: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`; split large modules into descriptive service files. Environment roots also contain `providers.tf`, `locals.tf`, `backend.tf`, sanitized `terraform.tfvars.example`, `backend.hcl.example` and mocked tests. Future scripts and templates belong in `scripts/` and the owning module's `templates/` directory. This document contains no executable Terraform configuration.

## 3. Toolchain, providers and environment profiles

### 3.1 Selected version baseline

| Component | Selected value / policy | Evidence and implementation gate |
|---|---|---|
| Terraform CLI | `1.17.2`; exact root requirement and `.terraform-version` | Listed in [HashiCorp releases](https://releases.hashicorp.com/terraform/). Install signed/checksummed distribution and run compatibility checks before committing source. |
| AWS provider | `hashicorp/aws`, `6.73.0` exact in roots | [Official provider listing](https://registry.terraform.io/providers/hashicorp/aws/6.73.0/docs). This is the researched baseline, not an automatic upgrade instruction. |
| Cloudflare provider | `cloudflare/cloudflare`, `5.29.0` exact in enabled workload root | [Official provider listing](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs). Use v5 schemas; do not copy v4 `cloudflare_record` examples. |
| Child module version contract | Minimum tested versions consistent with roots, AWS `< 7.0.0`, Cloudflare `< 6.0.0` | Root exact selections and lockfiles determine deployment builds. |
| AWS CLI / PowerShell | AWS CLI v2; PowerShell 7 | Record exact installed patch releases in validation evidence; not Terraform dependencies. |
| OS | Ubuntu Server 24.04 LTS, `amd64`, HVM, EBS-backed | Canonical account `099720109477`; validate image provenance and region. |
| RDS engine | MySQL `8.4.13`, family `mysql8.4` | [Supported RDS MySQL versions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/MySQL.Concepts.VersionMgmt.html); query eu-west-1 availability before plan. |
| Checkmk | Self-hosted Community edition, supported `2.5.0` patch line | Proposed edition; verify Ubuntu 24.04 package/support and licence. Pin exact `pN`, download URL and SHA-256 in configuration manifest before installation. See [system requirements](https://docs.checkmk.com/latest/en/release_notes.html). |
| Docker / Compose / EFS utils / agents | Exact signed packages and image digests in release manifest | No unpinned download scripts or runtime `latest` images. Select compatible security-maintained patch versions during implementation; availability not tested in this document. |

Commit `.terraform.lock.hcl` for every independently initialized root, including bootstrap and the optional Cloudflare root; include Linux AMD64 and Windows AMD64 hashes. Do not create a lockfile without initialization evidence. Do not use the deprecated DynamoDB locking design: use [S3 native locking](https://developer.hashicorp.com/terraform/language/backend/s3).

### 3.2 Profiles

| Setting | `prod` | `test` | `dev` |
|---|---|---|---|
| Subnets / AZs / Docker hosts | 9 / 3 / 3 | Same | Same for full graph; mocked/local by default |
| Zonal NAT gateways | 3 | 1 in C | 1 in C if deployed |
| ALBs / EFS mount targets | 3 / 3 | Same | Same |
| Docker EC2 | `t3.large`, root 50 GiB | `t3.small`, root 20 GiB | Test values |
| VPN EC2 | `t3.small`, root 20 GiB | `t3.micro`, root 15 GiB | Test values |
| Checkmk EC2 | `t3.medium`, root 50 GiB; data 50 GiB | `t3.medium`, root 30 GiB; data 20 GiB | Test values |
| RDS | `db.t4g.medium`, Multi-AZ, 100–500 GiB | `db.t4g.micro`, Single-AZ, 20–100 GiB | Test values |
| RDS retention | 14 days | 1 day | 1 day |
| EFS / EC2 daily backups | 30 / 14 days | 2 / 2 days | 2 / 2 days |
| Monthly backups | Enabled, 365 days | Disabled | Disabled |
| Deletion protections | ALB, EC2 API termination and RDS enabled | Disabled | Disabled |
| Log retention | 90 days application/network; audit 365 days | 14 days; audit integration retained per account policy | 14 days |
| Cloudflare | Required for public launch | Optional; restricted TLS origin test permitted | Optional |
| Cost budget | Owner-provided USD monthly amount | Owner-provided temporary test ceiling and monthly alert amount | No deployment by default |

A reduced smoke profile may disable expensive services only through documented flags and must report reduced coverage. Production profile validation must reject fewer than three AZs, single NAT, Single-AZ DB, TLS disabled, missing authentication or deletion protection. A full-fidelity test may explicitly enable production resilience; account and cost approval still apply.

## 4. Naming, tagging, data classification and identifiers

### 4.1 AWS names and Terraform identifiers

Set `project = strathost`, `region_code = euw1` for the selected region and `resource_prefix = strathost-{environment}-euw1`. Resource `Name` tags use the complete prefix. Terraform labels use descriptive snake_case: `hosting`, `wordpress`, `docker_hosts`, `public_web`, `secure_web`, `internal_web`, `workload_exports`, `checkmk_server`, `vpn_server`; do not use `foo`, `example` or ambiguous `this` throughout the implementation.

| Resource | Concrete production name | Planned local address / keys |
|---|---|---|
| VPC / IGW | `strathost-prod-euw1-vpc` / `strathost-prod-euw1-igw` | `aws_vpc.hosting`, `aws_internet_gateway.hosting` |
| Subnets | `strathost-prod-euw1-snet-{public\|app\|db}-{a\|b\|c}` | `aws_subnet.public["a"]`, `.application["a"]`, `.database["a"]`, etc. |
| Route tables | `strathost-prod-euw1-rt-public`, `...-rt-app-a`, `...-rt-db` | `public`, `application[az_key]`, `database` |
| NAT / EIP | `strathost-prod-euw1-nat-a`, `...-eip-nat-a` | `aws_nat_gateway.application_egress[az_key]`, `aws_eip.nat[az_key]` |
| Hosts | `strathost-prod-euw1-ec2-docker-01` through `03`; `...-ec2-vpn-01`; `...-ec2-checkmk-01` | `aws_instance.docker_hosts["docker_01"]`, `vpn_server`, `checkmk_server` |
| ALBs | `strathost-prod-euw1-alb-public`, `...-alb-secure`, `...-alb-internal` | `aws_lb.web[visibility]` |
| Target groups | `strathost-prod-euw1-tg-public`, `...-tg-secure`, `...-tg-internal` | `aws_lb_target_group.web[visibility]` |
| RDS / EFS | `strathost-prod-euw1-rds-mysql` / `strathost-prod-euw1-efs-wordpress` | `aws_db_instance.wordpress`, `aws_efs_file_system.wordpress` |
| SGs / roles / policies | `...-sg-{role}`, `...-role-{purpose}`, `...-policy-{purpose}` | Named `for_each` maps; retain stable keys |
| Workload buckets | `strathost-prod-euw1-{backup\|alb-logs\|origin-trust}-{account_id}` | `workload_exports`, `alb_access_logs`, `origin_trust` |
| Optional audit bucket | `strathost-prod-euw1-audit-{account_id}` | `audit_logs`; absent when using organization trail |
| State bucket | `strathost-tfstate-{account_id}-euw1` | Bootstrap `aws_s3_bucket.terraform_state` |
| KMS aliases | `alias/strathost/prod/{ebs\|rds\|efs\|backup\|exports\|secrets\|logs\|alerts}` | `aws_kms_key.workload[purpose]`, `aws_kms_alias.workload[purpose]` |
| Backup vault / plans | `...-vault-workloads`, `...-backup-efs`, `...-backup-ec2` | `workloads`, `efs`, `ec2` |
| CloudWatch groups | `/strathost/prod/{flowlogs\|cloud-init\|system\|docker\|vpn\|checkmk\|ssm}` | `aws_cloudwatch_log_group.platform[purpose]` |

ALB/target-group names must be at most 32 characters and must satisfy service character/prefix restrictions. The examples above fit. For arbitrary longer inputs use a deterministic prefix-plus-eight-hex-hash of the **full** intended name, within 32 characters; validate collision-free results. E.g. 23-character trimmed prefix + hyphen + eight-character hash. S3 names must be globally unique, lowercase and 3–63 characters; append account ID, validate availability and allow a stable owner-approved suffix if required. Do not use random suffixes that change every plan.

Use stable map keys `a`, `b`, `c` and `docker_01`–`docker_03`; resolve AZ names once and record AZ IDs. Do not derive persistent identities from a changing sorted list of AZs or numeric `count` indices. Resource replacement names, especially final DB snapshots, are explicit release inputs rather than `timestamp()` values.

### 4.2 Tag schema

Set AWS provider `default_tags` to the following baseline; explicitly set `Name`, resource classification and backup tags on resources and volumes. Merge required tags after caller `additional_tags` so callers cannot override `Project`, `Environment` or `ManagedBy`. Resources without tagging support are documented exceptions (routes, attachments, association resources and some service policies).

| Tag | Selected value |
|---|---|
| `Project` / `Application` | `StratHost` / `WordPressHosting` |
| `Environment` / `ManagedBy` | `dev`, `test` or `prod` / `Terraform` |
| `Owner` / `BusinessUnit` / `Repository` | `Infrastructure` / `StratHost` / `strathost-infrastructure` |
| `CostCenter` | Required owner input for production; `InterviewSandbox` proposed only for disposable test |
| `DataClassification` | `Confidential` for state, secrets, DB, EFS, snapshots and exports; `Internal` for network/control resources and sanitized operational logs |
| `Criticality` | `High` for production data/traffic; `Standard` for test; Checkmk `Medium` |
| `BackupPolicy` | `efs-daily`, `ec2-daily` or `none`; selection additionally constrains environment/project |
| `Name` | Generated AWS resource name |

State and logs can contain sensitive metadata; sanitize application logging regardless of classification. Per-site access points and credentials provide application separation; three shared EC2 instance roles do not provide strong hostile-tenant isolation. If mutually untrusted customers require isolation, redesign the compute/identity boundary before onboarding them.

## 5. Bootstrap, backend, identity and state lifecycle

**MASTER/DESIGN.** Bootstrap must be executable without depending on the bucket it creates. Initially keep bootstrap state on encrypted workstation storage, excluded from Git; after creating the bucket, migrate bootstrap state into its own key and retain a controlled recovery copy. Workload roots then use the provisioned backend.

| Terraform resource | Count | Explicit configuration and dependencies |
|---|---:|---|
| `aws_kms_key.terraform_state` | 1/account-region | `description = StratHost Terraform state encryption`; `key_usage = ENCRYPT_DECRYPT`; `customer_master_key_spec = SYMMETRIC_DEFAULT`; `enable_key_rotation = true`; `deletion_window_in_days = 30`; policy grants designated administrators and backend principals only. Protect from accidental destroy. |
| `aws_kms_alias.terraform_state` | 1 | `name = alias/strathost/terraform-state`; `target_key_id` references state key. |
| `aws_s3_bucket.terraform_state` | 1 | Name from section 4; `force_destroy = false`; bootstrap protection; no website configuration. |
| `aws_s3_bucket_versioning.terraform_state` | 1 | `bucket` references bucket; `versioning_configuration.status = Enabled`. |
| `aws_s3_bucket_server_side_encryption_configuration.terraform_state` | 1 | SSE algorithm `aws:kms`, state key ARN, `bucket_key_enabled = true`. |
| `aws_s3_bucket_public_access_block.terraform_state` | 1 | All four public-block booleans `true`. |
| `aws_s3_bucket_ownership_controls.terraform_state` | 1 | `object_ownership = BucketOwnerEnforced`; no ACL resource. |
| `aws_s3_bucket_policy.terraform_state` | 1 | TLS-only deny on bucket/objects; allow scoped backend role paths; enforce designated KMS key without requiring headers absent from legitimate backend requests; deny incorrect explicit key headers. |
| `aws_s3_bucket_lifecycle_configuration.terraform_state` | 1 | Rule filter all objects, `status = Enabled`; abort incomplete multipart after 7 days; noncurrent state versions retained 365 days before expiration; no current-state or lock expiration. |
| `aws_iam_policy.terraform_backend` | Per environment principal | Bucket `ListBucket` limited to environment and lock prefixes; object `GetObject`, `PutObject` on exact state key; add `DeleteObject` only for `.tflock`; KMS encrypt/decrypt/data-key on state key. Bootstrap migration principal also needs bootstrap key paths. Attach to approved role in identity-owning stack. |

Backend values: `bucket` from bootstrap; `key = environments/{environment}/terraform.tfstate`; `region = eu-west-1`; `encrypt = true`; `kms_key_id` = state key ARN; `use_lockfile = true`. Bootstrap uses `bootstrap/terraform.tfstate`; optional DNS root uses `dns/{environment}/terraform.tfstate`. Backend credentials are independently resolved by Terraform's backend, not inherited from AWS provider configuration. Set approved AWS profile/SSO or CI role session externally. Use backend account restrictions where supported and independently check caller identity.

Production and test should use separate AWS accounts. In a shared interview sandbox, distinct state keys and IAM permissions are mandatory but do not emulate full account isolation. No backend access for runtime EC2 roles. No state access through workload S3 endpoint policies.

Preserve state for rollback; do not restore an older state file merely to undo an infrastructure change. Use reviewed configuration changes, import/moved blocks and state repair only with reconciled AWS evidence. `sensitive = true` redacts normal CLI output; it does not encrypt values inside state or saved plans.

References: [Terraform S3 backend and lock permissions](https://developer.hashicorp.com/terraform/language/backend/s3), [AWS S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html), [Terraform sensitive state](https://developer.hashicorp.com/terraform/language/state/sensitive-data), [KMS key policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html). Resource references: [S3 bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket), [KMS key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key).

## 6. VPC, addressing and subnet provisioning

### 6.1 AZ and address contract

Select available standard AZs using `data.aws_availability_zones.available`, excluding Local/Wavelength Zones. The deployment input records keys `a`, `b`, `c` mapped to owner-confirmed AZ names and AZ IDs; names are account-relative. The examples use `eu-west-1a`, `eu-west-1b`, `eu-west-1c`, but do not hardcode universal physical identities.

| Key | Public subnet | Private app subnet | Isolated DB subnet | Fixed allocations |
|---|---|---|---|---|
| `a` | `10.0.1.0/24` | `10.0.4.0/24` | `10.0.7.0/24` | VPN `.1.10`; Docker `.4.10`; EFS `.4.20` |
| `b` | `10.0.2.0/24` | `10.0.5.0/24` | `10.0.8.0/24` | Docker `.5.10`; EFS `.5.20` |
| `c` | `10.0.3.0/24` | `10.0.6.0/24` | `10.0.9.0/24` | Docker `.6.10`; EFS `.6.20`; Checkmk `.6.30` |

Short allocations above expand within `10.0.0.0/16`; e.g. VPN is `10.0.1.10`. Reserve `.10`–`.39` for documented infrastructure; do not allocate static addresses to ALB or RDS ENIs. Each `/24` has 251 AWS-usable addresses. ALBs need free subnet capacity; alert if available addresses fall below 32 and block launch below AWS requirements. No IPv6 CIDR, egress-only gateway or IPv6 route is selected. Cloudflare edge may still serve IPv6 clients while using IPv4 origins.

| Resource | Count | Selected arguments |
|---|---:|---|
| `aws_vpc.hosting` | 1 | `cidr_block = 10.0.0.0/16`; `instance_tenancy = default`; `enable_dns_support = true`; `enable_dns_hostnames = true`; `assign_generated_ipv6_cidr_block = false`; tags. |
| `aws_subnet.public` | 3 | `vpc_id`; per-key CIDR/AZ; `map_public_ip_on_launch = false`; `assign_ipv6_address_on_creation = false`; tier-specific tags. |
| `aws_subnet.application` | 3 | Same, app CIDRs; no automatic public IPs. |
| `aws_subnet.database` | 3 | Same, DB CIDRs; no automatic public IPs. |
| `aws_internet_gateway.hosting` | 1 | `vpc_id = hosting.id`; tags. Attached to VPC, not AZ. |
| `aws_default_security_group.quarantined` | 1 adopted | `vpc_id`; remove all ingress and egress; explicit empty rule sets; never attach to workloads. Adopt before workloads launch. |
| `aws_default_route_table.quarantined` | 1 adopted | `default_route_table_id` from VPC; manage with no non-local routes; tag `...-rt-quarantine`. Every real subnet has an explicit association below. |

Use default AmazonProvidedDNS DHCP behavior; no custom DHCP options resource is required. VPC local route and default VPC objects are AWS-created; do not count them as separately created VPCs or extra subnet resources. Adopt defaults only in this new dedicated VPC, not in a shared/default account VPC.

References: [AWS subnet sizing](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html), [AWS AZs](https://docs.aws.amazon.com/ram/latest/userguide/working-with-az-ids.html), [Terraform VPC](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc), [subnet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet), [IGW](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway), [default SG](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group), [default route table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table).

## 7. NAT, routes, endpoints and network ACLs

### 7.1 NAT and route resources

| Resource | Prod / test count | Explicit configuration / dependencies |
|---|---:|---|
| `aws_eip.nat` | 3 / 1 | `domain = vpc`; keys `a,b,c` or `c`; tags. No `instance` association. |
| `aws_nat_gateway.application_egress` | 3 / 1 | `allocation_id = nat[key].id`; `subnet_id = public[key].id`; `connectivity_type = public`; tags; explicit dependency on attached IGW. Each is a zonal NAT in the indicated subnet. |
| `aws_route_table.public` | 1 | VPC and tags; no inline routes when using standalone route resources. |
| `aws_route_table.application` | 3 | VPC, one per AZ, tags. |
| `aws_route_table.database` | 1 | VPC and tags; only implicit local route; no internet/NAT/VPN default. |
| `aws_route.public_internet` | 1 | `route_table_id = public.id`; `destination_cidr_block = 0.0.0.0/0`; `gateway_id = hosting_igw.id`. |
| `aws_route.application_internet` | 3 | Per-AZ app table; `destination_cidr_block = 0.0.0.0/0`; `nat_gateway_id = same-AZ NAT` in prod or NAT C in test. |
| `aws_route_table_association.subnets` | 9 | Public A/B/C → public table; app A/B/C → matching app table; DB A/B/C → DB table. Reference subnet/table IDs, never rely on main-table inheritance. |
| `aws_vpc_endpoint.s3` | 1 | `vpc_id`; `service_name = com.amazonaws.eu-west-1.s3`; `vpc_endpoint_type = Gateway`; `route_table_ids = three app tables plus public table`; endpoint policy below; tags. |

An S3 gateway endpoint has no ENIs or SG. It adds AWS-managed S3 prefix-list routes to selected tables. Do not duplicate those routes with `aws_route` or mix `route_table_ids` with separately owned endpoint route associations. Including the public table lets VPN management use regional S3 without public transport; DB table deliberately omitted.

Endpoint policy permits only selected workload export prefixes and required SSM/agent bootstrap buckets, with exact bucket ARNs recorded after validating the regional SSM bucket list. Permit required `GetObject` for verified AWS-managed artifacts, and role-scoped `ListBucket`/`PutObject` for workload exports. Distinguish endpoint policy (maximum access through endpoint) from IAM and bucket policies (actual authorization). Do not use broad `Deny` rules that prevent SSM updates. State, ALB-log and audit buckets are not workload destinations.

**DESIGN baseline:** EC2 uses NAT/IGW outbound HTTPS for SSM, CloudWatch, Secrets Manager and update repositories; interface endpoints are not required for baseline operation. **OPTION:** enable `aws_vpc_endpoint.interface[service]` for `ssm`, `ssmmessages`, `logs`, `secretsmanager`, `kms`, `monitoring` as needed, with `vpc_endpoint_type = Interface`, app subnet IDs across three AZs, `private_dns_enabled = true`, endpoint SG TCP 443 from managed-host SGs, and per-service supported policy. Verify whether the deployed SSM agent also needs `ec2messages` in eu-west-1. Add `ec2` only for consumers that call it. These endpoints incur hourly/per-AZ cost and do not replace internet access for Ubuntu, Docker, Checkmk downloads or external checks. No cost-saving claim is assumed.

### 7.2 NACL ownership and selected rules

**MASTER/DESIGN:** Keep the default NACL's allow-all behavior while managing it for drift. This is a deliberate stateful-SG-first design, not a claim that NACLs isolate the database tier.

Use one `aws_default_network_acl.hosting` with `default_network_acl_id` from the new VPC. Inline ingress and egress each have `rule_no = 100`, `protocol = -1`, `action = allow`, `cidr_block = 0.0.0.0/0`, `from_port = 0`, `to_port = 0`; AWS terminal `*` deny remains implicit. All nine subnets use this default ACL. If managing `subnet_ids`, set the entire nine-subnet list in the same resource; do not concurrently own associations elsewhere. Do not mix inline rules with `aws_network_acl_rule`.

Adoption temporarily replaces default rules, so perform it before traffic exists. A future custom NACL design requires its own ADR and explicit `aws_network_acl`, `aws_network_acl_rule` and `aws_network_acl_association` resources. Test both directions, client/server ephemeral TCP `1024–65535`, UDP VPN replies, NAT return traffic and ICMP path MTU. Adding isolated ingress rules without stateless return rules is not an accepted implementation.

References: [AWS NAT routing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html), [S3 gateway endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html), [SSM connectivity](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html), [NACL behavior](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html), [Terraform NAT](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway), [EIP](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip), [route](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route), [route table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table), [route association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association), [endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint), [default NACL](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl).

## 8. Security groups and traffic contracts

Create `aws_security_group` shells with `name`, descriptive `description`, `vpc_id`, `revoke_rules_on_delete = true`, tags and no inline rules. Terraform removes the default allow-all egress; add every selected egress explicitly using standalone `aws_vpc_security_group_egress_rule`. Use `aws_vpc_security_group_ingress_rule` for ingress; each rule has `security_group_id`, `ip_protocol`, port range, one `referenced_security_group_id`/`cidr_ipv4`/`prefix_list_id`, and a descriptive reason. Never mix standalone and inline rule management.

### 8.1 SG inventory

| SG key | Attached to | Inbound enforcement |
|---|---|---|
| `public_alb` | Public ALB | Cloudflare IPv4 ranges → TCP 443; or explicit approved test CIDRs when Cloudflare disabled. |
| `secure_alb` | Secure ALB | Cloudflare IPv4 ranges → TCP 443; same restricted-origin-test exception only with application authentication. |
| `internal_alb` | Internal ALB | VPN SNAT IP `10.0.1.10/32` and Checkmk SG → TCP 443. Additional private client CIDRs require explicit input. |
| `docker_hosts` | Three Docker hosts | Three differentiated ALB ingress rules, Checkmk agent rule. |
| `mysql` | RDS | Docker SG → TCP 3306 only. |
| `wordpress_efs` | EFS mount targets | Docker SG → TCP 2049 only. |
| `vpn_server` | VPN EC2 | Approved VPN client public CIDRs → UDP 51820; Checkmk SG → TCP 6556. |
| `checkmk_server` | Checkmk EC2 | VPN SNAT IP → TCP 443; managed-host SGs → TCP 443 and 8000 for agent registration. |
| `interface_endpoints` | Optional interface endpoint ENIs | Docker, VPN, Checkmk SGs → TCP 443. Absent in baseline. |

### 8.2 Exact workload flow matrix

Every row represents both a destination ingress rule and a source egress rule unless the source is external or traffic is a stateful reply. Return traffic does not need SG ephemeral-port rules.

| Source | Destination | Protocol/port | Rule purpose |
|---|---|---|---|
| Maintained Cloudflare IPv4 CIDRs | Public and secure ALB SGs | TCP 443 | Origin HTTPS; mTLS and application access checks are additional controls. |
| Owner-approved public client CIDRs | VPN SG | UDP 51820 | WireGuard transport. Production must not default to world-open clients. |
| Public ALB SG | Docker SG | TCP 8080 | Public proxy only. |
| Secure ALB SG | Docker SG | TCP 8081 | Protected proxy only. |
| Internal ALB SG | Docker SG | TCP 8082 | Internal proxy only. |
| Docker SG | MySQL SG | TCP 3306 | TLS database sessions. |
| Docker SG | EFS SG | TCP 2049 | TLS/IAM mount-helper NFS traffic. |
| Checkmk SG | Docker and VPN SGs | TCP 6556 | TLS agent pull. Checkmk monitors itself locally. |
| Docker and VPN SGs | Checkmk SG | TCP 443, TCP 8000 | REST/receiver agent enrollment and certificate registration. Treat each port separately. |
| VPN SG / translated `10.0.1.10/32` | Internal ALB SG, Checkmk SG | TCP 443 | Approved VPN services; SG egress references and destination /32 ingress agree with SNAT. |
| Checkmk SG | Internal ALB SG | TCP 443 | Internal synthetic HTTP/TLS check. |
| Docker, VPN and Checkmk SGs | `0.0.0.0/0` | TCP 443 | Signed package mirrors, AWS APIs, registries, Access JWKS; NAT for private hosts. Document this broad outbound exception. |
| Docker SG; optionally other managed roles if artifact fetch required | Regional S3 managed prefix list | TCP 443 | Exports/verified bootstrap artifacts through endpoint. Covered by HTTPS egress but separately documented for endpoint-only tightening. |

No inbound TCP 22, 80, 3306, 2049, 2375/2376 or 6556 from the internet. No VPC-wide all-protocol SG ingress. Do not open EFS to Checkmk or DB to VPN just to simplify monitoring; Checkmk obtains those service metrics from AWS APIs. No direct VPN access to Docker application ports or RDS.

AWS-provided VPC DNS and link-local Amazon Time Sync are used; SGs do not filter several AWS-reserved services in the same way as ordinary destination traffic. Host firewalls must allow DNS to `10.0.0.2` and NTP to `169.254.169.123`; do not substitute a public DNS server or public NTP exception silently. Optional ICMP diagnostics need their own narrowly scoped rules. HTTPS egress cannot restrict by arbitrary FQDN; use approved repositories, endpoints or an egress proxy if tighter filtering is required.

Cloudflare range changes must be retrieved from [official IP ranges](https://www.cloudflare.com/ips/), reviewed and committed as versioned input; no unreviewed HTTP data source mutates SGs during plan. There are no IPv6 SG rules because origins are IPv4-only. Confirm SG-rule quotas against current Cloudflare range count, optional features and three ALB rules before apply.

References: [AWS security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html), [Terraform SG](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group), [ingress rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule), [egress rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule), [Checkmk Linux agent ports](https://docs.checkmk.com/latest/en/agent_linux.html).

## 9. Encryption keys and key-policy design

Create eight workload `aws_kms_key.workload[purpose]` resources and eight aliases per environment: `ebs`, `rds`, `efs`, `backup`, `exports`, `secrets`, `logs`, `alerts`. Keep bootstrap state key separate. All use `SYMMETRIC_DEFAULT`, `ENCRYPT_DECRYPT`, rotation enabled, 30-day deletion window, descriptive purpose and mandatory tags. `multi_region = false`; no replicas selected. Never generate or export key material.

| Key | Consumers and explicit authorization |
|---|---|
| `ebs` | EC2 encrypted root/data volumes and associated snapshots; provisioning and backup roles need applicable grant/data-key permissions. EC2 runtime users do not require general decrypt access merely to use attached EBS. |
| `rds` | RDS storage/snapshots and Database Insights encryption where compatible; deployer may create AWS-service grants with `kms:GrantIsForAWSResource = true`. |
| `efs` | Regional filesystem storage; EFS/service integrations and backup access as required. |
| `backup` | Backup vault recovery points where independent encryption applies; EBS snapshots may retain source key encryption. Preserve both source and vault keys through retention. |
| `exports` | Workload S3 exports; exporter role encrypt/data-key, recovery role decrypt. `kms:ViaService = s3.eu-west-1.amazonaws.com`; encryption-context restrictions account for S3 Bucket Keys using bucket ARN. |
| `secrets` | RDS-managed master secret and empty application secret containers; RDS/Secrets Manager integration plus narrowly authorized runtime GetSecretValue/decrypt. |
| `logs` | CloudWatch Logs groups; `logs.eu-west-1.amazonaws.com` principal with `kms:EncryptionContext:aws:logs:arn` constrained to project log-group ARNs; optional CloudTrail use needs separate service statement. |
| `alerts` | SNS topic; producer services such as CloudWatch, EventBridge and AWS Backup get only required GenerateDataKey/Decrypt under scoped service conditions. |

Key policies explicitly separate administrator principals from cryptographic users. Retain an account-recovery policy allowing controlled IAM delegation; do not lock out the administrator or grant all workloads `kms:*`. Use account ID, deterministic ARNs and role shells to avoid resource/key-policy cycles. Grant `kms:CreateGrant`, `DescribeKey` and encryption operations only when required by the relevant AWS integration. Test IAM **and** key policies; either can make a correctly encrypted resource unusable.

CloudWatch encrypted logging, RDS-managed secrets, backup/restore and encrypted SNS delivery require service-specific key statements; a key that permits only the deployer is insufficient. Do not apply a blanket `aws:SourceArn` condition to operations where the service does not provide it; use the exact documented service context. Default KMS policy JSON is not an acceptable unreviewed implementation.

ALB access-log and origin-trust buckets intentionally use SSE-S3. ALB log delivery supports SSE-S3 for the selected access-log path; forcing SSE-KMS on that bucket breaks delivery. TLS is separately enforced. See [AWS ALB log requirements](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html), [CloudWatch KMS integration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html), [AWS Backup encryption](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html), [Terraform KMS alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias).

## 10. IAM roles, permissions, secrets and operator access

### 10.1 IAM resources and trust relationships

Use `aws_iam_role` (`name`, `path = /strathost/{environment}/`, `assume_role_policy`, `max_session_duration = 3600`, tags), `aws_iam_policy` (`name`, same path, generated policy), `aws_iam_role_policy_attachment` and `aws_iam_instance_profile` (`name`, `path`, `role`, tags). No IAM users or access keys are created. Use `data.aws_iam_policy_document` to build structured policy documents, not interpolated JSON strings.

| Role | Trusted principal | Selected permissions and boundaries |
|---|---|---|
| `docker_runtime` + one shared instance profile | `ec2.amazonaws.com` | SSM managed-node functions; log writes to named streams; CloudWatch custom metric PutMetricData restricted by namespace; EFS ClientMount/ClientWrite constrained to allowed access-point ARNs; read only assigned site secrets; export permission for selected backup node described below. No master secret access. |
| `vpn_runtime` + profile | EC2 service | SSM, named logs/metrics; read VPN key secret ARN only. No RDS, EFS, site-secret or export access. |
| `checkmk_runtime` + profile | EC2 service | SSM/logs/metrics; read Checkmk bootstrap secret ARN; scoped AWS monitoring API calls. No application-secret or database login rights. |
| `rds_enhanced_monitoring` | `monitoring.rds.amazonaws.com` | Attach AWS `AmazonRDSEnhancedMonitoringRole`; trust constrained by source account and deterministic DB ARN where supported. |
| `backup_service` | `backup.amazonaws.com` | Backup EFS and EC2/EBS resources, tag recovery points and use required KMS grants; attach AWS `AWSBackupServiceRolePolicyForBackup`, then constrain with reviewed custom policy/boundary where supported. Managed backup policy scope is an explicit reviewed exception. |
| `backup_restore` | Approved operator role via STS | Separate restore permissions and `AWSBackupServiceRolePolicyForRestores` only for recovery operators; KMS grants, network and restore permissions. No runtime role can restore or delete backups. |
| `vpc_flow_logs` | `vpc-flow-logs.amazonaws.com` | CreateLogStream, PutLogEvents, DescribeLogStreams on flow-log group; account/source-VPC conditions supported by service. Log group pre-created, so no broad CreateLogGroup. |
| `deployment` | Approved SSO principal or existing CI OIDC provider | Resource provisioning limited to environment/account/region, explicit PassRole allowlist of these roles and services; backend path access; no general workload use. |
| `operator` | Approved workforce identity | SSM StartSession/Resume/Terminate scoped to tagged EC2 and approved documents, log read, read-only infrastructure status. Remote-host forwarding permissions restricted; no general administrator grant. |

The baseline uses approved SSO deployment/operator roles supplied by the account owner. Creating/altering these account-level identities or an OIDC provider is an optional identity-bootstrap feature, not an implicit workload-stack permission. If enabled, `aws_iam_openid_connect_provider` uses GitHub issuer `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`; role trust limits `sub` to the exact repository and protected GitHub environment. PR workflows get no apply role; untrusted forks receive no credentials. Import/reuse existing issuer instead of duplicating it.

### 10.2 Runtime policy detail

1. **SSM:** `AmazonSSMManagedInstanceCore` may be attached as a documented AWS-managed baseline; review its account-wide channel/association capabilities. Prefer an equivalent reviewed custom policy only after checking agent requirements. Session Manager connectivity is outbound; never add inbound SSH for SSM.
2. **Logging:** `logs:CreateLogStream`, `logs:PutLogEvents`, required describe calls on `/strathost/{environment}/...` groups and the exact approved shared Session Manager group ARN only. Pre-create groups. `cloudwatch:PutMetricData` needs resource `*` with `cloudwatch:namespace = StratHost/Platform`; do not pretend that action supports resource ARNs. Describe APIs that require `*` are individually listed and region-constrained.
3. **Checkmk APIs:** `ec2:DescribeInstances`, `DescribeInstanceStatus`, `DescribeVolumes`, `DescribeTags`; `elasticloadbalancing:DescribeLoadBalancers`, `DescribeTargetGroups`, `DescribeTargetHealth`, `DescribeListeners`; `rds:DescribeDBInstances`, `DescribeEvents`; `elasticfilesystem:DescribeFileSystems`, `DescribeMountTargets`; `cloudwatch:GetMetricData`, `GetMetricStatistics`, `ListMetrics`, `DescribeAlarms`; `backup:ListBackupJobs`, `ListRestoreJobs`, `ListRecoveryPointsByBackupVault`; `s3:ListBucket` on exports if freshness checks require it. Use resource scoping where supported, and narrow explicit `*` exceptions where not. No broad AWS `ReadOnlyAccess` attachment and no `SecretsManagerReadWrite`.
4. **S3 exports:** designated Docker01 configuration runs export jobs. Because hosts share one runtime profile, prefix authorization alone cannot isolate Docker01 from the other two. Baseline permits all three hosts to write approved site prefixes but schedules only one exporter; record this trust boundary. A future per-host export role/profile is required if single-host authorization is a security requirement. Allow `PutObject`, `AbortMultipartUpload`, `ListMultipartUploadParts`, bucket-prefix ListBucket, plus required KMS GenerateDataKey/Encrypt. Do not allow DeleteObject, restore or arbitrary GetObject on backups to runtime exporters.
5. **EFS:** allow ClientMount/ClientWrite on exact filesystem ARN with `elasticfilesystem:AccessPointArn` matching assigned access points; no ClientRootAccess. Filesystem policy also restricts role, TLS and access point. POSIX permissions remain required.

### 10.3 Secret resource ownership

RDS creates and rotates its own master secret: do not create a competing `aws_secretsmanager_secret_version`, password variable or `random_password`. Terraform reads only the secret **ARN**, never a secret-value data source.

Create `aws_secretsmanager_secret.application[site_key]` for each declared site, plus `vpn_server` and `checkmk_bootstrap`: `name = /strathost/{environment}/{site|vpn|checkmk}/{purpose}`; `kms_key_id = secrets key`; `recovery_window_in_days = 30` production, 7 test; descriptive tags; replicas absent. **Do not create secret versions in Terraform.** A separate audited initialization step writes application credentials, WireGuard keys and Checkmk automation credentials. Secret ARNs and service metadata can be state; credentials cannot be user data, tfvars, outputs or plan artifacts.

The database initializer alone may read the managed master secret and write site secret values. Use a temporary SSM task/operator session on an approved host with a time-limited initialization role; do not leave master access on Docker runtime roles. Create per-site database/schema and users with only required schema grants; revoke initialization access afterwards. Rotate credentials through a coordinated configuration workflow; rotation of the RDS master does not rotate site users.

References: [AWS IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html), [RDS-managed master secrets](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html), [RDS monitoring trust](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.Enabling.html), [SSM role permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html), [GitHub AWS OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [Terraform IAM role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role), [policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy), [attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment), [instance profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile), [secret metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret).

## 11. S3 workload, log and origin-trust buckets

**ARCH:** workload backup S3. **DESIGN:** separate buckets for independent retention, encryption and delivery policies. Bootstrap state is already specified in section 5. Buckets are regional and are never assigned to an AZ or subnet.

### 11.1 Resource set per bucket

For each selected workload bucket create `aws_s3_bucket`, `aws_s3_bucket_public_access_block`, `aws_s3_bucket_ownership_controls`, `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_lifecycle_configuration` and `aws_s3_bucket_policy`. Reference bucket IDs between resources. Set all four public-access-block flags `true`, ownership `BucketOwnerEnforced`, `force_destroy = false` in all profiles. Temporary buckets must be deliberately emptied during approved teardown. No legacy inline ACL, versioning, lifecycle or encryption blocks on `aws_s3_bucket`.

| Bucket | Encryption and versioning | Selected retention / purpose |
|---|---|---|
| `workload_exports` | SSE-KMS `exports` key, Bucket Key enabled; versioning Enabled | Prefix `sites/{site_key}/daily/{UTC-date}/`; current exports expire after 30 days prod, 2 days test; noncurrent versions expire after same interval; expired delete markers cleaned separately; multipart abort 7 days. No IA transition for 30-day exports. |
| `alb_access_logs` | SSE-S3 `AES256`; versioning Enabled | Prefix `alb/{public\|secure\|internal}/AWSLogs/{account_id}/...`; 90 days prod, 14 test; noncurrent versions same duration; multipart abort 7 days. No KMS requirement or encryption-header deny that breaks ELB delivery. |
| `origin_trust` | SSE-S3 `AES256`; versioning Enabled | Only when origin mTLS enabled. Public CA bundle/CRL artifacts, no private keys. Keep current CA bundle indefinitely; noncurrent versions 365 days; multipart abort 7 days. Rotation must preserve active trust references. |
| `audit_logs` | SSE-KMS `logs` key, versioning Enabled | Only if standalone CloudTrail requested. Prefix `cloudtrail/`; current/noncurrent objects retained 365 days; no workload runtime write access. Organization-owned retention overrides this proposal. |

All bucket policies deny insecure requests using `aws:SecureTransport = false` on bucket and object ARNs. Enforce runtime TLS without inadvertently rejecting AWS service delivery when request context differs; use documented service-principal exceptions where required. Export policy allows only approved role/prefix combinations and requires encryption with the chosen key through defaults and denial of conflicting explicit encryption headers. Use no world-readable statements.

ALB log policy allows principal `logdelivery.elasticloadbalancing.amazonaws.com`, action `s3:PutObject`, exact resource `arn:aws:s3:::{bucket}/alb/{visibility}/AWSLogs/{account_id}/*`. Add source account/ALB ARN restrictions only as supported by the service's documented policy. Bucket must be in eu-west-1. The ALB depends on the completed bucket policy and encryption configuration; merely referencing bucket name does not establish that ordering.

For origin trust, `aws_s3_object.origin_ca_bundle` uses `bucket`, `key = trust/strathost-origin-ca.pem`, a reviewed **public** PEM source artifact, content checksum (`source_hash`), `content_type = application/x-pem-file`, `server_side_encryption = AES256`; capture `version_id`. Trust-store creation references bucket/key/version. An optional `aws_s3_object.origin_crl` follows the same versioned-public-artifact pattern. Do not manage leaf/private-key upload to Cloudflare through Terraform.

Application backups are explicit files, not automatic copies of RDS snapshots or EFS recovery points. Docker01 runs an authenticated export job at 01:00 UTC with `mysqldump --single-transaction` for InnoDB, a compatible MySQL 8.4 client, TLS verification and a site manifest/checksum. Filesystem exports require a coordinated write pause or a documented consistency method. Store no database password on command line or in logs. Publish `ExportSuccess` only after upload/checksum verification and record a final success marker per site. Do not schedule exports on all three replicas. S3 object versioning alone is not application consistency or ransomware-proof immutability.

References: [AWS S3 encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html), [Object Ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html), [lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html), [ALB log delivery](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html). Terraform references: [versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning), [encryption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration), [public block](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block), [ownership](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls), [policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy), [lifecycle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration), [object](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object).

## 12. EFS shared WordPress storage

**ARCH/MASTER:** one Regional filesystem with mount targets in app A/B/C. Do not provision three filesystems. Mount targets and EFS access points are different resource types.

| Resource | Count | Selected arguments / dependencies |
|---|---:|---|
| `aws_efs_file_system.wordpress` | 1 | `creation_token = {resource_prefix}-wordpress`; `encrypted = true`; `kms_key_id = efs key ARN`; `performance_mode = generalPurpose`; `throughput_mode = elastic`; omit `availability_zone_name` (Regional); lifecycle `transition_to_ia = AFTER_30_DAYS`, `transition_to_primary_storage_class = AFTER_1_ACCESS`; no archive transition initially; tags incl. `BackupPolicy = efs-daily`. |
| `aws_efs_mount_target.wordpress` | 3 | `file_system_id`; matching `application[az].id`; fixed `ip_address` `.4.20`, `.5.20`, `.6.20`; `security_groups = [wordpress_efs SG]`; one target per AZ. |
| `aws_efs_access_point.site` | Per declared site | `file_system_id`; `posix_user.uid = 10000 + stable site allocation`, `gid` same; `root_directory.path = /sites/{site_key}`; `creation_info.owner_uid/owner_gid` match; `permissions = 0750`; site tags. Stable UID comes from configuration, never changing map order. |
| `aws_efs_file_system_policy.wordpress` | 1 | Exact filesystem ID; deny non-TLS; deny mounts not using approved access-point ARNs and non-mount-target access as supported; permit ClientMount/ClientWrite for Docker role with TLS and access-point conditions; no anonymous access or ClientRootAccess. |
| `aws_efs_backup_policy.wordpress` | 1 | `file_system_id`; `backup_policy.status = DISABLED` to disable EFS's separate automatic plan; explicit AWS Backup plan in section 20 remains enabled. |

Default synthetic site keys are `public_wordpress`, `secure_wordpress`, `internal_wordpress`, with stable POSIX IDs `10001`, `10002`, `10003`. These are **DESIGN** demonstration workloads, not diagram-required tenants. Real sites replace/extend the map through reviewed configuration. Do not expose a shared EFS root access point to all containers.

Install a pinned Ubuntu-compatible `amazon-efs-utils` package or verified build artifact. Mount with `tls,iam,accesspoint={site access-point ID},_netdev` to `/srv/wordpress/shared/{site_key}` using instance-role credentials. Do not embed static AWS keys. Use mount-helper/systemd dependencies and retries; application service has `RequiresMountsFor` and checks the path is actually an EFS mount. A mount failure must not let WordPress write uploads onto the root EBS volume.

Store only mutable persistent content (primarily uploads) on EFS; keep WordPress core/plugins/themes in versioned immutable images. Access-point UID/GID enforcement must agree with container filesystem permissions. No unmanaged plugin installation on a single replica. NFS/TLS connectivity and cross-AZ file consistency are acceptance tests. EFS throughput/small-file costs and latency need measurement before claiming the platform supports a given number of sites.

References: [AWS EFS mount targets](https://docs.aws.amazon.com/efs/latest/ug/manage-fs-access-create-delete-mount-targets.html), [IAM NFS access](https://docs.aws.amazon.com/efs/latest/ug/iam-access-control-nfs-efs.html), [access points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html), [automatic backups](https://docs.aws.amazon.com/efs/latest/ug/automatic-backups.html). Terraform references: [filesystem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system), [mount target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target), [access point](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point), [policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system_policy), [backup policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_backup_policy).

## 13. RDS MySQL database

**ARCH/MASTER:** one `aws_db_instance.wordpress` with a non-readable synchronous standby in production. RDS owns standby placement and failover; never assume its IP, manually create standby EC2 or use `aws_rds_cluster` for this design. Configure subnet group across all three isolated DB subnets. Do not pin `availability_zone` when `multi_az = true`.

### 13.1 Supporting resources

| Resource | Count | Selected arguments |
|---|---:|---|
| `aws_db_subnet_group.wordpress` | 1 | `name = {prefix}-dbsubnet-mysql`; `description = StratHost isolated MySQL subnets`; `subnet_ids = DB A/B/C`; tags. |
| `aws_db_parameter_group.wordpress` | 1 | `name = {prefix}-mysql84`; `family = mysql8.4`; parameters below; tags. Parameter-group family changes are a migration, not an in-place minor edit. |
| `aws_cloudwatch_log_group.rds` | 2 | `/aws/rds/instance/{db_identifier}/{error\|slowquery}`; KMS logs key; retention 90 prod/14 test; created before DB log export. |
| IAM role/attachment | 1 | Enhanced Monitoring role from section 10. Pre-create `RDSOSMetrics` group with retention if this new dedicated account does not already own one; otherwise use account policy and avoid claiming stack ownership. |

Parameters: `require_secure_transport = ON` (dynamic, immediate); `character_set_server = utf8mb4`; `collation_server = utf8mb4_0900_ai_ci`; `slow_query_log = 1`; `long_query_time = 2`; `log_output = FILE`; `general_log = 0`. Verify parameter types/modifiability using the selected engine's parameter-family metadata; use `pending-reboot` only where required. Do not change `max_connections` arbitrarily; measure memory/connections. Keep performance schema enabled for supported Database Insights operation. Application DB bootstrap uses the same character set/collation.

### 13.2 DB instance configuration

| Argument | Production selection | Test selection / notes |
|---|---|---|
| `identifier`, `engine`, `engine_version` | `{prefix}-rds-mysql`, `mysql`, `8.4.13` | Same engine/minor unless regional query rejects it; record replacement selection. |
| `instance_class` | `db.t4g.medium` | `db.t4g.micro`; must confirm orderable class/engine/Multi-AZ/storage combination in eu-west-1. |
| `multi_az` | `true` | `false`; `availability_zone` may select A only in test if explicit. |
| `allocated_storage`, `max_allocated_storage`, `storage_type` | `100`, `500`, `gp3` | `20`, `100`, `gp3`. Omit configurable `iops` and `storage_throughput` at these capacities unless supported and deliberately provisioned. Do not copy EC2 gp3 arguments blindly. |
| `storage_encrypted`, `kms_key_id` | `true`, RDS key ARN | Same. Encryption/key changes require replacement/migration review. |
| `db_name`, `username` | `strathost`, `strathost_admin` | Metadata only; per-site schemas/users initialized separately. |
| `manage_master_user_password` | `true` | No `password`, `password_wo` or Terraform secret-value reads. |
| `master_user_secret_kms_key_id` | Secrets key ARN | RDS-managed rotation remains enabled (default seven-day rotation); verify actual configuration. |
| `db_subnet_group_name`, `parameter_group_name` | References above | Same. |
| `vpc_security_group_ids`, `port`, `network_type` | `[mysql SG]`, `3306`, `IPV4` | Same. |
| `publicly_accessible` | `false` | Same. |
| `backup_retention_period`, `backup_window` | `14`, `02:00-03:00` UTC | `1`, same window. |
| `maintenance_window` | `sun:04:00-sun:05:00` UTC | Same, non-overlapping with backup window. |
| `auto_minor_version_upgrade` | `false` | Explicit reviewed patch upgrades; emergency patch process required. AWS mandatory lifecycle actions may still apply. |
| `allow_major_version_upgrade`, `apply_immediately` | `false`, `false` | Same by default; test-only maintenance override reviewed. |
| `deletion_protection`, `skip_final_snapshot` | `true`, `false` | `false`, `false` by default; explicit disposable-data input may set skip true in test only. |
| `final_snapshot_identifier` | `{prefix}-mysql-final-{approved_release_id}` | Required when not skipping; identifier unique and valid, no continually changing timestamps in configuration. |
| `copy_tags_to_snapshot`, `delete_automated_backups` | `true`, `false` | `true`, `true` for disposable test only; cleanup retention still reviewed. |
| `enabled_cloudwatch_logs_exports` | `error`, `slowquery` | Same; no verbose general query logging. |
| `monitoring_interval`, `monitoring_role_arn` | `60`, Enhanced Monitoring role | `0`, omit role when disabled in reduced test; full test enables it. |
| `database_insights_mode` | `standard` | Same; no assumption that retired Performance Insights console features remain available. |
| `performance_insights_enabled`, retention/key | `true`, 7 days, RDS key ARN where compatible with Standard mode | Test may disable collection. Validate selected provider/API combination; Advanced mode and paid longer retention are excluded. |
| `iam_database_authentication_enabled` | `false` | WordPress uses restricted site credentials over TLS, not unimplemented IAM-auth plugins. |
| `ca_cert_identifier` | `rds-ca-rsa2048-g1` | Confirm current regional certificate and client bundle; track expiry/rotation. |
| `engine_lifecycle_support` | `open-source-rds-extended-support-disabled` | Avoid unplanned Extended Support enrolment; plan supported engine upgrades. |

RDS's Graviton DB class does not require ARM WordPress clients; SQL runs over the network. EC2 hosts remain AMD64. GP3 allocated storage cannot be shrunk in place; restoring a smaller schema onto a new database is a separate operation. A Multi-AZ failover drops connections; clients must resolve the endpoint and retry with bounded backoff. Configure TLS certificate/hostname verification with the current AWS RDS CA bundle. `require_secure_transport` alone does not prove clients validate server identity.

Do not run a Terraform MySQL provider from an unconnected workstation to initialize the private DB. Use the separate secure initialization workflow, and test compatibility of PHP/MySQL client with MySQL 8.4 `caching_sha2_password`. RDS snapshots/PITR are primary database backups; do not additionally enroll the instance in AWS Backup by default and claim those snapshots appear in the S3 export bucket.

References: [AWS Multi-AZ DB instances](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html), [supported MySQL versions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/MySQL.Concepts.VersionMgmt.html), [RDS storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html), [RDS TLS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html), [Database Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DatabaseInsights.html), [Terraform DB instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance), [DB subnet group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group), [parameter group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group).

## 14. EC2, operating system, sizing and EBS

### 14.1 Fleet and storage allocation

| Stable key | AZ/subnet | Private IP | Public address | Instance / prod disks |
|---|---|---|---|---|
| `docker_01` | A/app A | `10.0.4.10` | None | `t3.large`, root 50 GiB |
| `docker_02` | B/app B | `10.0.5.10` | None | `t3.large`, root 50 GiB |
| `docker_03` | C/app C | `10.0.6.10` | None | `t3.large`, root 50 GiB |
| `vpn_01` | A/public A | `10.0.1.10` | One EIP | `t3.small`, root 20 GiB |
| `checkmk_01` | C/app C | `10.0.6.30` | None | `t3.medium`, root 50 GiB + data 50 GiB |

`t3.large` is 2 vCPU/8 GiB, `t3.medium` 2 vCPU/4 GiB, `t3.small` 2 vCPU/2 GiB, `t3.micro` 2 vCPU/1 GiB. These are burstable starting points, not capacity guarantees. Check CPU credits and memory under workload. Switch to a measured non-burstable family through a documented sizing decision if sustained demand warrants it. Test sizes are specified in section 3.

### 14.2 AMI selection

Resolve `data.aws_ami.ubuntu_candidate` only in release preparation using Canonical owner `099720109477`, name family `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`, `architecture = x86_64`, `virtualization-type = hvm`, `root-device-type = ebs`, state available. If the official image catalogue uses a different verified name family in the chosen release, record the actual filter rather than broadening to arbitrary owners. Pin the resulting regional AMI ID in the release manifest; deployed instances use the pinned ID, not a `most_recent` query that causes surprise replacement. Inspect `data.aws_ami.selected` for owner, architecture, root device and deprecation before plan.

Do not fabricate an `ami-...` value in examples. `ami_ids_by_role` is a required deployment input and can initially use one tested Ubuntu image. Separate prebuilt role AMIs are allowed if their source manifest, patches and bootstrap are controlled.

### 14.3 EC2 resource arguments

Use `aws_instance.docker_hosts` (three), `aws_instance.vpn_server` (one), `aws_instance.checkmk_server` (one). Each receives `ami`, profile-selected `instance_type`, subnet reference, private IP, role SG IDs, instance profile and mandatory tags.

| Argument/block | Selected value / intent |
|---|---|
| `associate_public_ip_address` | `false` for all five. The VPN EIP is associated separately. |
| `key_name` | Omitted; no AWS key-pair resource and no SSH ingress. |
| `monitoring` | `true` prod, `false` test unless full telemetry test. |
| `source_dest_check` | `false` VPN because it forwards traffic; `true` others. |
| `disable_api_termination` | `true` prod, `false` test; controlled change needed before approved termination/replacement. This is not a universal Terraform destroy guard. |
| `instance_initiated_shutdown_behavior` | `stop`. |
| `credit_specification.cpu_credits` | `standard` selected to avoid unbounded surplus-credit charges; alert on low credits. Changing to unlimited requires explicit cost decision. |
| `metadata_options` | `http_endpoint = enabled`, `http_tokens = required`, `http_put_response_hop_limit = 1`, `instance_metadata_tags = disabled`. |
| `root_block_device` | `volume_type = gp3`, size by profile, `encrypted = true`, `kms_key_id = ebs key`, `iops = 3000`, `throughput = 125`, `delete_on_termination = true`, explicit volume tags and BackupPolicy. |
| `user_data` | Versioned, non-secret idempotent bootstrap; renders only resource identifiers, endpoints and configuration references. No credentials or private keys. |
| `user_data_replace_on_change` | `true`; any change schedules reviewed replacement, not a promise to rerun cloud-init in place. |
| `ebs_optimized` | `true` for selected supported types. |
| `hibernation`, public IPv6 | Disabled/absent. |

IMDS hop limit 1 prevents ordinary bridged containers from fetching instance-role credentials. **Selected credential boundary:** host services mount EFS and retrieve/decrypt site secrets, then supply only required secret files to containers in memory-backed storage. Application containers need no AWS SDK credentials or IMDS access. Do not raise hop limit to 2 or expose host networking merely to make a container exporter work; the export job is a host service. Explicitly deny container access to IMDS in host firewall as defence in depth.

Do not use `create_before_destroy` for fixed-IP EC2 instances: both replacements cannot own the same address. Drain one Docker target from all target groups, replace/configure/verify, then return it to service before touching the next host. Terraform does not guarantee application-aware rolling replacements; the deployment runbook must orchestrate them. Root filesystems hold OS/container caches/log buffers, not sole copies of uploads or DB data.

### 14.4 Additional storage and VPN EIP

| Resource | Count | Configuration |
|---|---:|---|
| `aws_ebs_volume.checkmk_data` | 1 | `availability_zone` = Checkmk AZ; type gp3; size 50 prod/20 test; 3000 IOPS/125 MiB/s; encrypted with EBS key; tags include BackupPolicy; no automatic snapshot source. |
| `aws_volume_attachment.checkmk_data` | 1 | `device_name = /dev/sdf`, `volume_id`, `instance_id`; `force_detach = false`, `stop_instance_before_detaching = true`; do not use destructive forced detach. |
| `aws_eip.vpn` | 1 | `domain = vpc`; name/tag `...-eip-vpn`; no inline instance association. |
| `aws_eip_association.vpn` | 1 | `allocation_id`, `instance_id = vpn.id`, `private_ip_address = 10.0.1.10`; depends on IGW attachment. |

Format Checkmk data volume as ext4 once, identified by EBS volume ID/UUID rather than assuming `/dev/sdf` exists on Nitro. Mount at `/srv/checkmk`; place supported Checkmk site data beneath it through a tested bind mount/service layout. Do not format a restored/nonempty volume. Configuration must wait for attachment because initial cloud-init can start before `aws_volume_attachment` completes. Use retrying systemd setup or a separate configuration stage, not a Terraform sleep. Back up root plus data as one EC2 backup selection; file-level application export covers Checkmk site configuration consistency.

### 14.5 OS and container configuration contract

Verify SSM Agent installed/enabled and online; Ubuntu AMIs are not assumed to have every required agent/version. Install CloudWatch Agent, TLS-enabled Checkmk agent and trusted CA bundle. Enforce time sync, unattended security patch policy with maintenance/reboot coordination, log rotation, least-privilege service users, root-login restrictions and nftables rules. Docker's packet rules can bypass simplistic UFW rules; enforce exposure in AWS SGs and validate the Docker/nftables integration explicitly.

Install pinned Docker Engine and Compose plugin from signed official repositories. `/var/run/docker.sock` stays local and root-restricted; do not expose API TCP. Use immutable digest-pinned WordPress/PHP and reverse-proxy images, non-root workloads where supported, read-only root filesystems where practical, dropped capabilities and per-container memory/CPU limits. Initial planning ceiling is 6 GiB combined application memory on an 8 GiB host, leaving 2 GiB for OS/agents/cache; test ceilings must be reduced to measured capacity. There is no invented throughput/SLA claim.

Deploy the selected sites to all three hosts, with dedicated public/secure/internal proxy listeners. Restrict vhosts and hostnames on each listener; never publish a secure container through port 8080. Health endpoint `/healthz` checks relevant container readiness, EFS mount and bounded DB connectivity; it returns 200 only when this host can serve the visibility class. It supports ALB target-IP health probes without accepting arbitrary production vhosts. Public access to the health URI is rejected by the application listener rules; ALB health checks reach targets directly. Configure WordPress canonical URL, trusted proxy headers, HTTPS awareness, application authentication and no credentials in logs. Disable request-triggered WP-Cron and run an idempotent scheduled job on designated Docker01; this is a single scheduling dependency, documented and monitored.

References: [Canonical AWS images](https://documentation.ubuntu.com/aws/), [AWS T3 instances](https://aws.amazon.com/ec2/instance-types/t3/), [IMDS options](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-options.html), [Docker Ubuntu installation](https://docs.docker.com/engine/install/ubuntu/), [EFS utils](https://docs.aws.amazon.com/efs/latest/ug/using-amazon-efs-utils.html), [Terraform EC2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance), [AMI data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami), [EBS volume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume), [attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment), [EIP association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip_association).

## 15. Certificates, origin trust and private DNS prerequisites

### 15.1 Domain model

`base_domain` is an **INPUT** owned by the deployment owner, not an invented StratHost domain. Define `public_hostname = www.{base_domain}`, `secure_hostname = secure.{base_domain}`, private zone `internal.{base_domain}`, `internal_hostname = wordpress.internal.{base_domain}`, `checkmk_hostname = checkmk.internal.{base_domain}`. Site maps may override these with validated distinct names. Never use a domain from another project or create production DNS during documentation work.

Use three separate ACM public certificates for the three ALB hostname classes, provisioned in eu-west-1. Public ACM can validate names used only in private DNS if a public DNS validation record exists in the controlled parent domain. This discloses certificate names through certificate transparency; use neutral names and do not include sensitive customer identifiers. No public leaf CNAME is needed for the internal service. Checkmk UI uses a separate certificate issued/renewed through the configuration workflow (ACME DNS-01 or approved internal CA); Terraform does not extract ACM private keys for host use.

| Resource | Count | Configuration |
|---|---:|---|
| `aws_acm_certificate.web` | 3 | `domain_name = hostname`; `validation_method = DNS`; `key_algorithm = RSA_2048`; no private-key fields; tags; `create_before_destroy` permitted for certificates. SANs are explicit site hostnames within visibility class. |
| `cloudflare_dns_record.acm_validation` | One per unique validation tuple | Existing zone ID, `name = resource_record_name`, `type = CNAME`, `content = resource_record_value`, `ttl = 60`, `proxied = false`. Deduplicate shared validation records and keep them for renewal. |
| `aws_acm_certificate_validation.web` | 3 | `certificate_arn`; `validation_record_fqdns` from created or owner-provided records; create timeout 45 minutes. Listener must reference the validated certificate dependency. |
| `aws_lb_trust_store.cloudflare_origin` | 1 conditional | `name` generated within service length constraints; `ca_certificates_bundle_s3_bucket`, `..._key`, `..._object_version` reference public CA object; tags; use dedicated CA signing only authorized origin client certificates. |
| `aws_lb_trust_store_revocation.cloudflare_origin` | Optional per active CRL | `trust_store_arn`; `revocations_s3_bucket`, `revocations_s3_key`, `revocations_s3_object_version`; rotation/revocation artifacts public, versioned and externally signed. |
| `aws_route53_zone.internal` | 1 | `name = internal.{base_domain}`; VPC association to hosting VPC/region; `force_destroy = false`; tags; private hosted zone only. |
| `aws_route53_record.internal_wordpress` | 1 | Zone ID, internal hostname, type A; alias to internal ALB `dns_name`/`zone_id`; `evaluate_target_health = true`. No TTL on alias record. |
| `aws_route53_record.checkmk` | 1 | Private zone, Checkmk hostname, type A, `ttl = 60`, `records = [10.0.6.30]`. |

For an external DNS owner, ACM records can be an explicit manual contract: output validation tuples and accept validated certificate ARNs; do not simultaneously create and import the same certificate. Certificate mode enum: `managed_dns`, `external_validated_arn`, `restricted_test_http`. Production rejects the third mode; default test uses TLS too. In external ARN mode use `data.aws_acm_certificate` or supplied ARNs with account/region/hostname validation and no `aws_acm_certificate_validation` ownership.

### 15.2 Origin mTLS handshake and secret handoff

**DESIGN:** use Cloudflare per-hostname Authenticated Origin Pulls (AOP) with a dedicated private CA and ALB `verify` mode, following [Cloudflare's ALB integration](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/aws-alb-integration/). The trust store contains only CA certificates. AOP leaf certificate and private key are generated in an approved PKI workflow and uploaded to Cloudflare outside Terraform; associate them with approved public/secure hostnames. Confirm the account's AOP entitlement and hostname support before production deployment.

Do not trust the globally shared Cloudflare origin-pull CA as proof of this specific zone. Do not commit CA signing keys, AOP leaf private keys, Access service tokens or OAuth client secrets. Keep a 30-day certificate-expiry alarm and a tested overlap/rotation procedure; use CRL resources when revocation is required. Terraform may consume the public CA artifact and track the external AOP certificate ID as metadata, but must not manage a private-key-bearing Cloudflare upload resource in state.

Until AOP is configured, the internet-facing ALBs may exist with no forwarding rules (default deny), allowing certificate and infrastructure provisioning to proceed. A distinct release input `publish_origin_routes` defaults false and becomes true only after origin TLS, AOP and protected application authorization checks are staged. It must not be conflated with deleting the ALB or opening test HTTP. Cloudflare-disabled test uses approved source CIDRs and TLS, with explicit exemption from AOP, and cannot pass a production-origin security gate.

VPN clients resolve private names via a DNS forwarder bound only to WireGuard address `10.250.0.1`, forwarding the private suffix to VPC resolver `10.0.0.2`. No public DNS forwarding listener. No Route 53 Resolver inbound endpoint is required for this selected single-VPN design; enterprise/on-prem resolver integration would need a separate design.

References: [ACM DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html), [ALB mTLS](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/mutual-authentication.html), [Cloudflare per-hostname AOP](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/set-up/per-hostname/), [Route 53 private zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html), [Terraform ACM certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate), [validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation), [trust store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_trust_store), [revocation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_trust_store_revocation), [private zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone), [DNS record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record).

## 16. ALBs, listeners, target groups and workload isolation

### 16.1 ALB resources

Use `aws_lb.web` with stable keys `public`, `secure`, `internal`. All have `load_balancer_type = application`, `ip_address_type = ipv4`, three subnets, visibility-specific SG, tags, deletion protection prod true/test false. Select `enable_http2 = true`, `drop_invalid_header_fields = true`, `desync_mitigation_mode = strictest`, `idle_timeout = 60`, `xff_header_processing_mode = append`. Confirm legitimate application headers/requests work under strict parsing; change only by ADR. Application code trusts forwarded headers only from the known proxy chain.

| Key | `internal` | Subnets | Target port | Log prefix |
|---|---:|---|---:|---|
| `public` | `false` | Public A/B/C | 8080 | `alb/public` |
| `secure` | `false` | Public A/B/C | 8081 | `alb/secure` |
| `internal` | `true` | App A/B/C | 8082 | `alb/internal` |

Set `access_logs.enabled = true`, `bucket = alb_access_logs.id`, prefix as above; depend on bucket policy. ALB cross-zone balancing is enabled by the service; target-group setting remains enabled/use-load-balancer-configuration. Internet-facing ALBs obtain service-managed public addresses despite `map_public_ip_on_launch = false`; they do not use VPN or NAT EIPs. Internal ALBs have private addresses only.

### 16.2 Target groups and registrations

Create three `aws_lb_target_group.web[visibility]` resources with `name`, `vpc_id`, `target_type = instance`, `protocol = HTTP`, `protocol_version = HTTP1`, matching dedicated port. `deregistration_delay = 60`; `slow_start = 30`; load-balancing algorithm round_robin; stickiness disabled. Set `health_check.enabled = true`, protocol HTTP, port traffic-port, path `/healthz`, matcher `200`, interval 30 seconds, timeout 5, healthy threshold 2, unhealthy threshold 3. Do not use a success range that marks login redirects/errors healthy.

Nine `aws_lb_target_group_attachment.web` resources: the Cartesian product of three groups and three Docker hosts, stable keys such as `secure/docker_02`; arguments `target_group_arn`, `target_id = instance.id`, explicit matching port. Do not register VPN/Checkmk or use an ALB ARN as a target of an ALB. Container/proxy processes must actually bind these ports; a target attachment does not deploy them.

Backend HTTP inside SG-restricted private subnets is an explicit **DESIGN** choice consistent with the master plan's proposed backend protocol, not end-to-end TLS. EFS, DB and external ALB hops remain encrypted. If policy demands ALB-to-target encryption, revise to HTTPS target groups and a managed host certificate workflow; ALB HTTPS target behavior does not itself authenticate target certificates. Do not claim backend identity validation without an additional mechanism.

### 16.3 Listeners and rules

Create three `aws_lb_listener.https[visibility]`: `port = 443`, `protocol = HTTPS`, validated class certificate ARN, `ssl_policy = ELBSecurityPolicy-TLS13-1-2-2021-06`, default action fixed-response 403 with text/plain generic body. Public/secure additionally use `mutual_authentication.mode = verify`, trust-store ARN, `ignore_client_certificate_expiry = false`, `advertise_trust_store_ca_names = off` when AOP is enabled. Internal listener has no Cloudflare mTLS requirement.

Create three `aws_lb_listener_rule.forward[visibility]` only when that visibility's publishing gate is satisfied: priority 100 (or deterministic per-site priorities if splitting rules), host-header condition with the approved class hostnames, action forward to its target group. Listener default never forwards. Public class rules cannot list secure/internal names. Application proxy rejects non-matching Host on every backend port. For protected class, JWT validation is required even with a matching hostname. Health endpoints use target health-check traffic, not an externally allowed listener rule.

No HTTP 80 listener or SG rule in baseline. Cloudflare performs HTTP-to-HTTPS at the edge. Optional `restricted_test_http` creates three HTTP listeners only for explicitly approved test CIDRs/private sources; it is a labelled exception and is forbidden in prod. No silent redirect to an absent certificate. Additional ACM SNI certificates require `aws_lb_listener_certificate` per additional certificate if SAN limits/ownership demand it; none are required for the initial three certificates.

ALB fixed default deny is an exposure control, not end-user authentication. Secure backend verifies Cloudflare Access JWT signature/JWKS, expected issuer/team, exact audience, expiry and issued-time constraints; strips/spoof-proofs identity headers and fails closed if no valid token. Protected routes cannot be enabled until this configuration is tested. An mTLS client certificate authenticates the origin client, not an application user. Internal WordPress still needs application login and authorization; VPN membership alone is not administrator authorization.

References: [AWS ALB configuration](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html), [listener rules](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-rules.html), [health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html), [TLS policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html), [Terraform ALB](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb), [target group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group), [attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment), [listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener), [listener rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule), [listener certificate](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate).

## 17. Cloudflare DNS, proxy, Access and activation

**ARCH/MASTER:** Cloudflare front door; optional before domain/credentials exist. **DESIGN:** existing account and zone are inputs; Terraform must not create a competing zone, change registrar delegation or assume permission to modify unrelated names/settings.

| Resource / integration | Configuration and selected values |
|---|---|
| `cloudflare_dns_record.public_web` | `zone_id` input, `name = public_hostname`, `type = CNAME`, `content = public ALB dns_name`, `proxied = true`, `ttl = 1` (automatic), descriptive comment. ALB name is AWS DNS, not an IP copied from DNS. |
| `cloudflare_dns_record.secure_web` | Same, secure hostname/ALB. Create only after secure access policy exists; keep origin default deny while configuring. |
| `cloudflare_dns_record.acm_validation` | DNS-only validation CNAMEs from section 15; lifecycle separate from proxied leaf records. |
| `cloudflare_zero_trust_access_policy.secure_users` | `account_id`, name `{prefix}-secure-users`, `decision = allow`, `session_duration = 8h`; `include` contains only explicit owner-approved email entries or an existing approved Access group ID. Empty allowlist fails validation. No Everyone, bypass or broad email-domain rule by default. |
| `cloudflare_zero_trust_access_application.secure_web` | `account_id`, `name = {prefix}-secure-wordpress`, `type = self_hosted`, `domain = secure_hostname`, `session_duration = 8h`, `allowed_idps = [one approved existing IdP ID]`, `auto_redirect_to_identity = true`, `http_only_cookie_attribute = true`; `policies` references reusable policy ID at precedence 1. Capture `aud` for origin validation. |
| `cloudflare_zone_setting` (conditional) | Separate resources using `zone_id`, `setting_id`, `value`: `ssl = strict`, `min_tls_version = 1.2`, `tls_1_3 = on`, `always_use_https = on`. `manage_zone_settings = false` by default on shared zones; require externally verified equivalent settings. Enable management only for a dedicated/explicitly delegated zone scope. |
| Per-hostname AOP (external secret-bearing step) | Uploaded certificate ID and hostname associations from section 15, verified by API/handshake evidence. No private-key state resources. |
| IdP/MFA | Existing workforce IdP with enforced MFA; owner supplies IDs and membership. Terraform does not invent an IdP application or set a broad bypass when MFA is unavailable. |

Use Cloudflare provider v5 object/list schemas (`content`, singular `cloudflare_zone_setting`, reusable policy references); inspect the pinned provider schema before implementation. API token is supplied through the provider's supported environment variable (`CLOUDFLARE_API_TOKEN`), scoped to the specific zone DNS edits and account Access application/policy edits, plus zone settings only when enabled. No global API key. The Terraform state still reveals Access policy membership metadata; protect it accordingly.

### 17.1 Avoid DNS/certificate dependency cycles

The selected baseline keeps `modules/cloudflare` within the **same workload root**, with the Cloudflare provider configured in that root for the enabled integration. The reference to a separate DNS state/root in section 5 is an optional future ownership split, not a baseline requirement. Module outputs must preserve resource-level dependency granularity:

1. ACM request → DNS validation records → ACM validation completion → ALB listener.
2. ALB creation → proxied leaf DNS record.
3. Access policy → Access application → origin audience configuration through the separate configuration workflow.

Do not set module-level `depends_on` from all load balancing to all Cloudflare resources and back. Prefer a small certificate-validation DNS child module and a separate edge/Access child module if this makes dependencies clearer. If ownership requires separate DNS state, use a staged certificate-request/output/record/validation handoff with explicit state contracts; do not leave a circular `terraform_remote_state` graph.

With Cloudflare disabled, supply external validated ACM ARNs or externally fulfilled DNS validation records and restrict origin ingress to explicit test client CIDRs. Do not instantiate a credential-bearing Cloudflare module or provide a fake token just to make AWS-only work pass. Mock Cloudflare in offline tests; integration planning requires actual scoped credentials.

### 17.2 Production activation sequence

Stage ALBs with default deny; provision certificates, trust store and protected application; configure origin JWT verification; upload/associate AOP certificate externally; allow reviewed Cloudflare SG CIDRs; test TLS/mTLS with approved credentials and verify token rejection; enable the narrowly scoped forwarding rules; publish DNS; verify real proxied access and authenticated/unauthenticated behavior. No ordinary user access before protections are ready.

Cloudflare Full (strict) verifies the ALB's server certificate; ALB mTLS verifies the dedicated origin client; Access verifies user identity; application authorization decides what that user can do. These are separate controls. Proxy DNS alone does not hide an origin, implement a WAF or guarantee a licence tier. Never claim WAF rules, bot protection, private routing or notifications were configured when only DNS was created.

References: [Cloudflare Terraform](https://developers.cloudflare.com/terraform/), [Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/), [Access token validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/), [DNS record resource](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record), [Access application](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_application), [Access policy](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zero_trust_access_policy), [zone setting](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/zone_setting), [Cloudflare v5 migration](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/guides/version-5-upgrade).

## 18. WireGuard VPN configuration contract

The VPN uses the EC2 instance, EIP, IAM profile, SG, logs and secret metadata already inventoried. No `aws_vpn_gateway`, `aws_customer_gateway`, Site-to-Site tunnel or `aws_ec2_client_vpn_endpoint` is part of this design. Those are different architectures, not Terraform resources required to make WireGuard function.

| Configuration item | Selected value |
|---|---|
| OS/software | Ubuntu 24.04 kernel WireGuard and pinned signed `wireguard-tools`; systemd-managed interface `wg0`. |
| Endpoint | VPN EIP, UDP 51820; optional owner-managed DNS A record `vpn.{base_domain}` must be DNS-only if created, never Cloudflare HTTP proxy. EIP endpoint suffices for baseline. |
| Tunnel range | `10.250.0.0/24`, server `10.250.0.1/24`, peer /32 allocations from `.10` upward; validate against VPC and every client/site network. |
| Client routes | Split tunnel: private DNS resolver `10.250.0.1/32`, app subnet CIDRs or explicitly narrower approved service CIDRs. No `0.0.0.0/0`, DB subnet routes or arbitrary internet forwarding. |
| IP forwarding | IPv4 forwarding enabled; source/destination check disabled on VPN EC2. |
| Forwarding model | SNAT authorized tunnel traffic to `10.0.1.10` only for internal ALB app-subnet addresses TCP 443 and Checkmk `10.0.6.30:443`. Filter before SNAT. No VPC route to `10.250.0.0/24` required. |
| Dynamic ALB addresses | Match internal-ALB app subnet CIDRs at host firewall plus destination SG and port controls, not stale resolved ALB IPs. Internal ALB destination SG permits only VPN SNAT `/32` and approved monitoring. |
| Host firewall | Default-drop forward chain; established/related return traffic; explicit wg0→approved private TCP 443 allow; deny DB CIDRs, Docker 8080–8082, metadata and other destinations; UDP listener and Checkmk agent exceptions; persist across reboot. |
| DNS | Local forwarder bound only to tunnel IP; allow DNS TCP/UDP 53 on wg0 from allocated peers; forward private suffix to VPC DNS. Prevent open recursion on public/private ENIs. Client uses split-DNS settings where supported. |
| Key lifecycle | Keys generated outside Terraform; server key stored in scoped secret; mode 0600 root-readable runtime file; client private keys remain on client; peer public keys and revocation inventory supplied securely. |
| MTU / liveness | Start MTU 1420; validate actual path/PMTUD; client `PersistentKeepalive = 25` only where NAT traversal needs it. |

SNAT intentionally loses peer IP at target services; log peer key/allocated tunnel IP/session metadata on VPN without payloads and preserve application user identity. Do not add `10.250.0.0/24` SG rules expecting that address after translation. If routed mode is later selected, replace SNAT, add explicit return routes targeting VPN ENI on all relevant tables and change destination SG CIDRs; it is not a flag with identical policies.

Bootstrap can install/enable the service but must not fabricate active peers. An empty peer list is valid infrastructure and an operationally inactive VPN, reported as such. Test allowed service access, DNS, disallowed DB/metadata/host ports, bad peer denial, revocation, reboot persistence, key rotation and endpoint recovery. Single VPN failure interrupts private administration; SSM remains the independent recovery path while outbound connectivity exists.

References: [WireGuard quick start](https://www.wireguard.com/quickstart/), [AWS source/destination checks](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html), [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html).

## 19. Checkmk, Systems Manager and host management

### 19.1 Checkmk service configuration

**MASTER/DESIGN:** run one Checkmk Community site `strathost` at `10.0.6.30`, backed by encrypted EBS data. Verify the pinned Community package includes required AWS/Docker checks; if a feature needs a paid edition, keep it explicitly unavailable until licensed rather than silently claiming coverage. Installation is configuration management, not an `aws_instance` property.

Install signed/verified Ubuntu 24.04 package from the release manifest; create site once; bind web UI to HTTPS 443 with approved host certificate; permit UI only through VPN or an approved SSM port-forward session. Site administration uses a secret-initialized automation account and named human roles; no default passwords. Receiver for site one uses TCP 8000. Use TLS Agent Controller pull on 6556; enroll Docker/VPN hosts through Checkmk REST/receiver using short-lived/scoped registration credentials, then remove enrollment-only secrets/permissions. Do not leave legacy plaintext agent fallback enabled. Self-monitor local site and data volume; self-monitoring cannot detect total server failure, so CloudWatch does that independently.

| Target | Minimum concrete checks / data source |
|---|---|
| Five EC2 hosts | CPU, load, memory, disk fullness/inodes, time sync, reboot required, systemd failures, SSM/agent status; TLS agents on remote managed hosts. |
| Docker fleet | Docker daemon, expected container count/state, restart loops, pinned image identity, proxy ports/readiness, per-host resource saturation; host-side Docker plugin with restricted local socket access. |
| WordPress sites | HTTP/TLS, expected response and login/auth separation, EFS mount freshness, bounded DB readiness; protected external synthetic requires a scoped non-human identity designed separately. |
| ALBs | Target health, unhealthy count, target/ELB 5xx, response time via AWS APIs/CloudWatch. |
| RDS | Availability, CPU, free memory/storage, connections, burst credits, events and backup freshness via AWS APIs; no Checkmk direct SQL ingress in baseline. |
| EFS | Mount availability on hosts; storage/throughput/client-connection metrics; backup freshness. |
| VPN | Interface/service active, UDP service, peer handshake age for designated always-on test peer; absence of idle peers alone is not an outage. |
| Backups | Last successful EFS/EC2 job and daily site success marker; warn >26 h, critical >30 h; S3 marker metadata access must be explicitly authorized if used. |
| Certificates | ACM/service metadata and externally presented certificate expiry warning 30 days, critical 14 days; include AOP/Checkmk certs. |

Default collection is 60 seconds for hosts and 5 minutes for AWS API checks; use API caching to avoid throttling and unexpected API charges. Alert recipients/escalation routes are owner inputs; this plan does not send messages. Secure Cloudflare synthetic probes must not bypass application authentication or store broad user sessions in Checkmk. API checks prove AWS control-plane visibility, not WordPress transaction success.

### 19.2 SSM resources and ownership

| Resource | Count / arguments |
|---|---|
| `aws_ssm_document.session_preferences` | One **account-region-owned** document `SSM-SessionManagerRunShell` if no existing owner; `document_type = Session`, `document_format = JSON`, Session schema `1.0`; content inputs select encrypted CloudWatch `/strathost/management/ssm`, `cloudWatchStreamingEnabled = true`, `cloudWatchEncryptionEnabled = true`, `idleSessionTimeout = 20`, `maxSessionDuration = 60`. Shared management root owns the group/key/document. Reuse existing preferences and report effective settings instead of competing stacks. |
| `aws_ssm_document.platform_configuration` | Optional controlled Command document, schema 2.2, versioned artifact references and non-secret inputs only. No automatic execution during planning. |
| `aws_ssm_association.security_patching` | Optional explicit account-managed maintenance feature only; AWS-RunPatchBaseline or approved document, tag-constrained targets, weekly Sunday 05:00 UTC scan, install/reboot through approved window. If used, document `name`, `targets`, `schedule_expression`, `apply_only_at_cron_interval = true`, and non-secret parameters. |

Selected baseline uses existing SSM patch policy if available; otherwise the configuration workflow enables unattended security downloads with controlled rolling install/reboot at Sunday 05:00 UTC. Do not configure both competing patch owners. An account-level Session Manager preference can be owned by only one stack; it cannot safely be instantiated independently in dev/test/prod within the same account-region. Use bootstrap/shared management ownership and provide IDs to workloads.

When no existing shared management owner exists, create a separately initialized `shared-management/` root before workloads: one `aws_kms_key.management_logs` and alias `alias/strathost/management/logs` (section9 key settings/policy with management log-group ARN), one `aws_cloudwatch_log_group.session_shell` named `/strathost/management/ssm` (365-day retention, management key, Project/ManagedBy/Owner tags and `Environment = shared`), and the single Session Manager preference document. Output group/key ARNs and preference document name. The optional `RDSOSMetrics` log group also belongs here with 90-day retention; do not change its ownership in every DB module. The seven per-environment groups include `/ssm` for environment-specific command/configuration logs; interactive shell logs use the shared group. Existing-management mode creates none of these shared resources and validates supplied effective settings/permissions.

Session shell output can be logged, but SSM port-forward and SSH sessions do **not** provide the same session-content logging. Record StartSession/StopSession API events via CloudTrail and application audit logs; do not claim Checkmk port-forward traffic is recorded as plaintext terminal history. Limit `AWS-StartPortForwardingSessionToRemoteHost` because it can bypass network-only administrative assumptions.

References: [Checkmk installation](https://docs.checkmk.com/latest/en/install_packages.html), [Checkmk AWS monitoring](https://docs.checkmk.com/latest/en/monitoring_aws.html), [Checkmk Docker](https://docs.checkmk.com/latest/en/monitoring_docker.html), [TLS agents](https://docs.checkmk.com/latest/en/agent_linux.html), [SSM logging limitations](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html), [Terraform SSM document](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document), [association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_association).

## 20. Backups, retention, restoration and recovery objectives

### 20.1 AWS Backup resources

| Resource | Count | Selected configuration |
|---|---:|---|
| `aws_backup_vault.workloads` | 1 | `name = {prefix}-vault-workloads`; `kms_key_arn = backup key`; `force_destroy = false`; tags. |
| `aws_backup_vault_policy.workloads` | 1 | Exact vault; restrict delete/update/recovery-point deletion to designated recovery administrators; permit documented backup service integration; avoid a deny that also blocks authorized test cleanup. Explicitly test policy principal conditions. |
| `aws_backup_plan.efs` | 1 | `name = {prefix}-backup-efs`; rule `rule_name = efs-daily`, `target_vault_name` reference, `schedule = cron(0 3 * * ? *)`, `schedule_expression_timezone = Etc/UTC`, `start_window = 60`, `completion_window = 360` minutes; `lifecycle.delete_after = 30` prod/2 test; recovery-point tags Project/Environment/Workload. |
| `aws_backup_plan.ec2` | 1 | `name = {prefix}-backup-ec2`; rule `rule_name = ec2-daily`, same vault; `schedule = cron(0 4 * * ? *)`, `schedule_expression_timezone = Etc/UTC`, `start_window = 60`, `completion_window = 360`; `lifecycle.delete_after = 14` prod/2 test. EC2 backup includes attached EBS volumes. |
| Monthly rules on those plans | Prod enabled | `cron(0 6 1 * ? *)`, UTC, start 120 min, completion 720 min, delete after 365 days; no cold-storage transition selected. This deliberately replaces imprecise calendar-month retention with an exact day count. |
| `aws_backup_selection.efs` | 1 | Plan/backup role references; `resources = [exact EFS ARN]`; `condition.string_equals` requires `aws:ResourceTag/Project = StratHost`, Environment matches, BackupPolicy `efs-daily`. |
| `aws_backup_selection.ec2` | 1 | Exact five EC2 instance ARNs; same Project/Environment conditions and BackupPolicy `ec2-daily`. No wildcard account-wide resource selection and no additional EBS selection duplicating attached-volume backups. |
| `aws_backup_vault_notifications.workloads` | 1 | Vault name, encrypted alerts SNS ARN, documented BACKUP_JOB_FAILED/EXPIRED and RESTORE_JOB_FAILED events; topic/key policy permits `backup.amazonaws.com`. EventBridge is additional structured status capture. |

AWS Backup service opt-ins are account-region settings. Query/confirm EC2/EFS opt-in before use. Do not let each environment manage `aws_backup_region_settings` and overwrite other environments' service settings. If this is a dedicated new account, bootstrap may own one opt-in resource with EC2/EFS enabled and an approved full service map; otherwise reuse existing settings.

**OPTION:** `aws_backup_vault_lock_configuration` governance/immutable protection requires its own retention/cleanup review; disabled in disposable test and excluded from initial baseline. An irreversible compliance lock is not an ordinary test default. Cross-account/cross-region copies need additional vaults, provider aliases, key policies, backup copy actions and a funded recovery design; excluded here.

EFS default automatic backup is disabled only because these explicit plans replace it. Native RDS automated backups/PITR remain enabled independently. EC2/EBS backups are crash-consistent unless application coordination is implemented; do not claim they are transaction-consistent WordPress database backups. Keep EBS/RDS/EFS source KMS keys through the latest retained recovery point; deleting a source key can invalidate recovery despite keeping a vault key.

### 20.2 Recovery contract

| Data/service | Backup mechanism | Provisional RPO / RTO | Required restore evidence |
|---|---|---|---|
| RDS | Native daily snapshot + transaction logs, 14-day PITR | RPO ≤5 min target; RTO 4 h | Restore to separate private DB identifier/subnets/SG, validate schema/rows/application TLS, then controlled cutover. LatestRestorableTime determines actual achievable RPO. |
| WordPress uploads | Daily EFS AWS Backup, 30 days; coordinated exports where needed | RPO 24 h; RTO 8 h | Restore into new isolated EFS/path, validate permissions/checksums/access points and paired DB content. |
| EC2/Checkmk | Daily EC2/EBS backups; rebuildable AMIs/configuration; Checkmk site export | RPO 24 h for configuration; RTO 4 h | Restore Checkmk data without overwriting existing volume, reattach/configure/re-register, verify real monitoring. |
| S3 logical exports | Daily site export, 30 days | RPO 24 h; RTO 8 h | Download with recovery role, verify manifest, load into isolated DB/site, reconcile uploads. |
| Terraform state | Versioning 365-day noncurrent retention | Last completed state write; restore target 1 h | Reconcile cloud inventory/locks and test a refresh-only plan from recovered state before changes. |
| VPN | Versioned non-secret peer inventory + protected key recovery | Config RPO 24 h; RTO 4 h | Rebuild host, re-associate EIP, restore/revoke keys as appropriate, test access policy. |

These are engineering targets awaiting business approval and timed restore tests. No cross-service atomic recovery is provided by independent RDS and EFS jobs. Choose a consistent site recovery point using export manifests/write pauses, and state the amount of potentially lost or unmatched uploads. Restore tests run monthly for synthetic sample data and quarterly for full recovery exercises after owner approval. Never overwrite production as a restore test.

References: [AWS Backup plans](https://docs.aws.amazon.com/aws-backup/latest/devguide/creating-a-backup-plan.html), [resource selection/opt-in](https://docs.aws.amazon.com/aws-backup/latest/devguide/assigning-resources.html), [encryption](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html), [RDS PITR](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html), [Terraform vault](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault), [vault policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_policy), [plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan), [selection](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection), [vault notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_notifications), [region settings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_region_settings), [vault lock](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration).

## 21. Logging, CloudWatch, audit, events and budgets

### 21.1 Required observability resources

| Resource | Configuration |
|---|---|
| `aws_cloudwatch_log_group.platform` | Seven groups listed in section 4; `name`, `retention_in_days = 90` prod/14 test, `kms_key_id = logs key`, tags; `skip_destroy = false` baseline, retention/cleanup controlled by runbook. No secrets in messages. |
| `aws_flow_log.hosting` | `vpc_id`, `traffic_type = ALL`, `log_destination_type = cloud-watch-logs`, destination flow-log group ARN, flow-log role ARN, `max_aggregation_interval = 60`; structured format includes version, account, interface, src/dst addresses/ports, protocol, packets, bytes, start/end, action, log-status, subnet/AZ IDs and TCP flags; tags. |
| `aws_sns_topic.infrastructure_alerts` | `name = {prefix}-alerts`, `kms_master_key_id = alerts key ARN`, tags; no FIFO. |
| `aws_sns_topic_policy.infrastructure_alerts` | Topic ARN; allow only required CloudWatch/EventBridge/Backup/budget producers with source-account/source-ARN constraints where documented; authorized operators may publish tests. |
| `aws_sns_topic_subscription.alert_email` | `protocol = email`, endpoint owner input, topic reference; subscription remains pending until recipient confirms. Do not report alert delivery before confirmation/test. Omit when input unavailable and mark production gate unsatisfied. |
| `aws_cloudwatch_metric_alarm.platform` | One per alarm/dimension below; alarm name `{prefix}-alarm-{component}-{condition}`, SNS `alarm_actions` and `ok_actions`, `actions_enabled = true`, descriptions include threshold/runbook; tags. |
| `aws_cloudwatch_dashboard.platform` | `dashboard_name = {prefix}-overview`, generated body with region, EC2, ALB, RDS, EFS, NAT, backup, export and spend widgets; links to runbooks. |
| `aws_cloudwatch_event_rule.backup_failures` | Default event bus; source `aws.backup`, backup/restore state-change detail types, failure/aborted/expired states as applicable; filter account/environment resources where event supports it. |
| `aws_cloudwatch_event_target.backup_failures` | Rule name, target SNS ARN, deterministic `target_id = infrastructure-alerts`; no role for direct SNS target if resource policy handles permission. |
| `aws_cloudwatch_event_rule.rds_events` / target | Source `aws.rds`, selected DB instance failover/failure/availability events for exact DB ID/ARN; SNS target/policy. Check actual emitted schema and avoid flooding all routine RDS events. |
| `aws_budgets_budget.environment_cost` | `name = {prefix}-monthly-cost`, `budget_type = COST`, `limit_unit = USD`, owner-supplied `limit_amount`, `time_unit = MONTHLY`; cost filter Environment cost-allocation tag (activated before use), 80% actual and 100% forecast notifications to approved email or permitted SNS. Budgets are alerts, not spending caps. |

Budget tag activation is an account/billing-owner prerequisite and can lag; a dedicated sandbox account should also have an account-wide budget to catch untagged charges. Budget notification delivery to an encrypted topic requires explicit SNS/KMS service permissions; direct approved email avoids claiming an untested integration. No guessed production spend amount.

### 21.2 Alarm specification

All thresholds are initial **DESIGN** values. Default comparison is greater-than-or-equal; statistic and datapoints are explicit. Native metric alarms use actual AWS dimension names/ARN suffixes. Custom agent metrics are only available after agents are configured.

Map each row to explicit alarm arguments: `namespace`, `metric_name`, `dimensions`, `comparison_operator`, `threshold`, `period`, `evaluation_periods`, `datapoints_to_alarm`, `treat_missing_data`, `alarm_actions` and `ok_actions`. Use `statistic` for Average/Minimum/Maximum/Sum, or `extended_statistic = p95` with `evaluate_low_sample_count_percentiles = ignore`; never both statistic fields. Unless stated otherwise, require every listed evaluation datapoint. Use LessThanThreshold/LessThanOrEqualToThreshold for falling-value alarms. All time periods in this table are seconds. During commissioning keep notifications suppressed through an explicit activation flag, then require publishers and activate them before production handover.

| Alarm / namespace | Metric, dimensions | Threshold / evaluation / missing-data behavior |
|---|---|---|
| EC2 failure / `AWS/EC2` | `StatusCheckFailed`, InstanceId, Maximum | ≥1, 60 s ×2, 2/2; missing data missing. Five alarms. |
| EC2 CPU / `AWS/EC2` | `CPUUtilization`, InstanceId, Average | ≥80%, 300 s ×3; missing missing. Five alarms. |
| EC2 CPU credits / `AWS/EC2` | `CPUCreditBalance`, InstanceId, Minimum | ≤20 credits, 300 s ×3; missing missing. Five alarms. |
| Host memory / `CWAgent` | `mem_used_percent`, InstanceId, Average | ≥85%, 300 s ×3; missing breaching after commissioning. Five alarms. |
| Host disk / `CWAgent` | `disk_used_percent`, InstanceId/path/device/fstype, Maximum | ≥80%, 300 s ×2; root on five hosts plus Checkmk data mount; device dimension matches actual agent emission. |
| Platform heartbeat / `StratHost/Platform` | `HostHeartbeat`, HostRole/InstanceId, Minimum | <1 or absent, 300 s ×2, missing breaching. Includes Checkmk failure independently. |
| ALB unhealthy / `AWS/ApplicationELB` | `UnHealthyHostCount`, LoadBalancer + TargetGroup, Maximum | ≥1, 60 s ×3; missing missing. Three alarms. |
| ALB unavailable / same | `HealthyHostCount`, same dimensions, Minimum | <1, 60 s ×2; missing breaching after activation. Three alarms. |
| ALB errors / same | Separate `HTTPCode_ELB_5XX_Count` and `HTTPCode_Target_5XX_Count`, LoadBalancer (and supported TG dimension), Sum | ≥10 in 300 s ×2; missing notBreaching for sparse error counts. Six alarms. |
| ALB latency / same | `TargetResponseTime`, LoadBalancer/TargetGroup, p95 | ≥2 s, 300 s ×3; missing notBreaching and low-sample percentile evaluation ignored. Three alarms. |
| RDS CPU / `AWS/RDS` | `CPUUtilization`, DBInstanceIdentifier, Average | ≥80%, 300 s ×3; missing missing. |
| RDS memory / same | `FreeableMemory`, DBInstanceIdentifier, Minimum | <536870912 bytes (512 MiB), 300 s ×3; missing missing. |
| RDS storage / `StratHost/Platform` | `RDSFreeStoragePercent`, DBInstanceIdentifier, Minimum | <20%, 300 s ×2; Checkmk/host publisher calculates native FreeStorageSpace divided by **current** DescribeDBInstances AllocatedStorage ×GiB, not initial Terraform allocation; missing breaching after commissioning. |
| RDS credits / same | `CPUCreditBalance`, DBInstanceIdentifier, Minimum | ≤20, 300 s ×3 for selected burstable classes. |
| RDS connections / same | `DatabaseConnections`, DBInstanceIdentifier, Average | ≥80% of verified effective max_connections; obtain value during commissioning and set threshold input, not a guessed default. |
| NAT / `AWS/NATGateway` | `ErrorPortAllocation`, NatGatewayId, Sum | ≥1, 60 s ×2; missing notBreaching. Per NAT. |
| NAT drops / same | `PacketsDropCount`, NatGatewayId, Sum | ≥100, 300 s ×2; missing notBreaching. Investigate/retune against traffic. |
| EFS throughput / `AWS/EFS` | `PercentIOLimit`, FileSystemId, Average | ≥80%, 300 s ×3 where metric applies to selected mode; complement with MeteredIOBytes/PermittedThroughput charts. No BurstCreditBalance alarm for Elastic mode. |
| Export/backup freshness / `StratHost/Platform` | `ExportAgeHours` by SiteKey; `BackupAgeHours` by BackupPlan, Maximum | >26 h warning and >30 h critical, 3600 s ×1, missing breaching. Checkmk/host job publishes; AWS event failure notifications alone do not detect a job that never ran. |
| Certificate expiry / `AWS/CertificateManager` or custom | `DaysToExpiry` certificate ARN; custom days for AOP/host cert | ≤30 warning/≤14 critical, 86400 s ×1; missing missing plus publisher-heartbeat alarm for custom check. |

Collect custom metrics only under `StratHost/Platform`, with stable bounded dimensions and 60-second resolution (hourly for freshness). Export jobs publish actual completion, not a fake metric on Terraform apply. Agent/configuration checks require logs and real failure injection before reporting monitoring coverage. CloudWatch dashboard existence alone proves no alerts.

### 21.3 Account-level security integration

**DESIGN:** before production, verify an existing organization multi-region CloudTrail management trail and GuardDuty detector cover this account/region. Default `account_security_mode = existing`; record owner/ARN/detector ID as inputs/evidence. Do not duplicate organization controls in every environment.

For an approved standalone interview account only, an optional shared-security root may create:

| Resource | Selected arguments |
|---|---|
| `aws_cloudtrail.account_management` | `name = strathost-account-management`, audit bucket/prefix, `is_multi_region_trail = true`, `include_global_service_events = true`, `enable_logging = true`, `enable_log_file_validation = true`, logs key; event selector management read/write All; selected S3 data events for export bucket are optional and costed. |
| Audit bucket policy / KMS statements | CloudTrail `GetBucketAcl`, `PutObject` for exact `cloudtrail/AWSLogs/{account_id}/*` with documented ACL/source ARN conditions; key GenerateDataKey/Describe and trail encryption context. Bucket ownership and log delivery must be tested together. |
| `aws_guardduty_detector.account` | `enable = true`, `finding_publishing_frequency = FIFTEEN_MINUTES`; tags; optional features are separately priced. Reuse/import existing detector. |
| GuardDuty EventBridge rule/target | Source `aws.guardduty`, detail-type GuardDuty Finding, severity ≥7, route to alert topic; resource policy/key permissions as above. |

AWS Config, Security Hub, WAF, automated remediation and organizational SCPs are optional account initiatives, not silently enabled workload resources. No legal/compliance certification follows from this plan.

References: [VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html), [CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html), [ALB metrics](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html), [SNS encryption](https://docs.aws.amazon.com/sns/latest/dg/sns-server-side-encryption.html), [AWS budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html), [CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html), [GuardDuty](https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html). Terraform references: [log group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group), [flow log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log), [SNS topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic), [topic policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy), [subscription](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription), [alarm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm), [dashboard](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard), [event rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule), [event target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target), [budget](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget), [trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail), [detector](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/guardduty_detector).

## 22. Consolidated resource inventory and count reconciliation

Counts are for the complete selected platform; they exclude AWS-managed service ENIs, local routes, standby internals and dynamically created log streams/recovery points. Those objects are real but are not independently managed Terraform resources. Conditional resources must be counted by feature flag in plan tests.

| Resource family | Production | Test | Ownership / dependency summary |
|---|---:|---:|---|
| VPC / subnet / IGW | 1 / 9 / 1 | Same | Workload; VPC → subnets/IGW. |
| NAT gateways / NAT EIPs | 3 / 3 | 1 / 1 | Public subnets + IGW → NAT → app routes. |
| Route tables, excluding adopted main | 5 | 5 | Public 1, app 3, DB 1. |
| Non-local explicit routes / associations | 4 / 9 | 4 / 9 | Public default 1, app defaults 3; local/S3 endpoint routes service-owned. |
| Default NACL / default SG / main route table adopted | 1 / 1 / 1 | Same | New VPC only; not additional created network objects. |
| S3 gateway endpoint | 1 | 1 | Four route-table associations inside endpoint config. |
| Interface endpoints / endpoint SG | 0 baseline | 0 | Conditional per-service count; three ENIs per service are AWS-managed. |
| Workload SGs | 8 | 8 | Public/secure/internal ALB, Docker, RDS, EFS, VPN, Checkmk. Rule count expands from explicit matrix and CIDR list. |
| Workload KMS keys / aliases | 8 / 8 | Same | Plus bootstrap state 1/1; optional account audit reuses logs key only in dedicated design. |
| Shared management key / alias / shell log group / preference document | 0 when existing; otherwise 1 / 1 / 1 / 1 per account-region | Shared | Separate management root; optional RDSOSMetrics adds one group if unowned. Not multiplied per environment. |
| EC2 / instance profiles | 5 / 3 | Same | Shared Docker profile + VPN + Checkmk; five root EBS volumes within instances. |
| Additional Checkmk EBS / attachment | 1 / 1 | Same | Data volume → attachment; readiness handled by configuration. |
| VPN EIP / EIP association | 1 / 1 | Same | Total public EIPs: 4 prod, 2 test. ALB public IPs are additional AWS-managed billed addresses. |
| Core service/runtime IAM roles | 6 | 6 | Docker, VPN, Checkmk, RDS Enhanced Monitoring, AWS Backup, VPC Flow Logs; test may retain unused monitoring role for graph fidelity. Restore/deploy/operator identities are existing or explicit optional additions. |
| IAM policies / attachments | By permission family | Same | One named policy per runtime permission family; AWS-managed SSM attachment per EC2 role, monitoring and backup attachments; no fake fixed count for optional identities. |
| Site/VPN/Checkmk secret containers | Sites + 2 (initially 5) | Same | RDS-managed master secret additional, service-owned; no Terraform secret versions. |
| RDS DB / subnet group / parameter group | 1 / 1 / 1 | Same | Production DB has AWS-managed standby; test does not. |
| EFS filesystem / targets / access points / policies | 1 / 3 / sites / 2 | Same | One filesystem policy, one backup policy; initially three site access points. |
| Workload S3 buckets | 2 + origin-trust if enabled | Same conditional | Exports + ALB logs; trust needed for AOP. Seven companion control resources total **including bucket**, per selected bucket; public artifacts additional. |
| Bootstrap bucket / companion controls | 1 / 6 | Shared account | Versioning, encryption, public block, ownership, policy, lifecycle. |
| ALBs / target groups / target registrations | 3 / 3 / 9 | Same | No chaining, three dedicated backend ports. |
| HTTPS listeners / forwarding rules | 3 / up to 3 | Same | Rules absent until activation gates; test HTTP replaces HTTPS only in explicit exceptional mode. |
| Managed ACM certs / validation waiters | 3 / 3 | Same | Zero when external ARNs supplied; DNS validation records variable count. |
| Origin trust store / bundle object | 1 / 1 when AOP | Optional | Trust bucket/object policy → trust store → listeners. Optional CRL object/revocation resource. |
| Private hosted zone / records | 1 / 2 | Same if domain available | Internal WordPress alias + Checkmk A record. No public internal-service record. |
| Cloudflare leaf DNS / Access app / policy | 2 / 1 / 1 | Optional | Plus ACM validation records and optional four zone-setting resources. |
| Backup vault / vault policy / plans / selections / notifications | 1 / 1 / 2 / 2 / 1 | Same | Optional monthly rules contained in plans; retained recovery points not Terraform resources. |
| Workload log groups / RDS log groups / flow log | 7 / 2 / 1 | Same | Account RDSOSMetrics group/Session Manager preferences singly owned or reused. |
| SNS topic / policy / email subscription | 1 / 1 / 0–1 | Same | Subscription requires recipient confirmation; omitted input means incomplete alerting. |
| Alarms / dashboard | Formula from section 21 / 1 | Same dimensions | Enabled alarm set depends on installed publishers, NAT count and activated services. Must not silently omit required production coverage. |
| EventBridge baseline rules / targets | 2 / 2 | Same | Backup failures and RDS events; optional GuardDuty adds 1/1. |
| Monthly budget | 1 | 1 if deployed | Cost allocation/billing owner prerequisite. |
| Optional CloudTrail / GuardDuty / audit bucket | 0 by default | 0 | Existing account controls verified; dedicated-security mode adds 1/1/1 and policies. |

The complete plan should contain no managed resources outside these families without an ADR and inventory update. Managed-service-linked roles created by AWS must be discoverable/authorized; do not blindly create duplicate service-linked roles. Required Cloudflare/ACM feature flags affect counts, not permission to expose an unprotected origin.

## 23. Typed variable catalogue and validation rules

Represent related settings as typed objects with optional fields only where defaults are defined. Do not expose every AWS API setting as a variable; constants such as IMDSv2, encryption, no public RDS and mandatory tagging are policy. Configuration arguments in prior sections remain authoritative even when not an input. Root examples contain placeholder **metadata** only, never executable fake account IDs, AMI IDs or secrets.

### 23.1 Identity, account, network and feature variables

| Variable | Type | Default / selected value | Validation / downstream use |
|---|---|---|---|
| `project` | string | `strathost` | Lowercase hyphenated, bounded length; naming locals. |
| `environment` | string | Required | Enum dev/test/prod; explicit environment profile. |
| `aws_region` | string | `eu-west-1` | Must match regional resource/certificate inputs; other region requires region_code/AZ/AMI/engine review. |
| `region_code` | string | `euw1` | Validated mapping, not freely inconsistent with region. |
| `expected_account_id` | string | Required, no invented default | 12 digits; AWS provider `allowed_account_ids`; assert STS caller. |
| `deployment_role_arn` | string or null | Existing approved role | ARN/account validation; provider assume_role only if supplied. Backend role configured independently. |
| `kms_admin_principal_arns` | set(string) | Required | Nonempty approved IAM role ARNs; no wildcard principal. |
| `owner`, `business_unit`, `cost_center` | strings | Infrastructure / StratHost / owner input | Nonempty; production CostCenter mandatory. |
| `additional_tags` | map(string) | Empty | Cannot override reserved tags; merge and validate. |
| `vpc_cidr` | string | `10.0.0.0/16` | Valid IPv4 /16 for faithful profile; alternate CIDR requires documented change. |
| `availability_zones` | map(object(name:string,id:string)) | Required a/b/c mapping | Exactly three distinct available standard AZs, correct region; verify IDs. |
| `subnets` | map(object(az_key:string,tier:string,cidr:string)) | Nine rows in section 6 | Exact three per tier; /24; contained in VPC; no overlap; stable keys. |
| `nat_strategy` | string | Profile-derived: per_az prod, single_c test/dev | Enum `per_az`, `single_c`; production only per_az. |
| `enable_s3_endpoint` | bool | true | Required baseline; disabling requires explicit reduced-profile exception. |
| `interface_endpoint_services` | set(string) | Empty | Allowlisted service names; endpoint policies/SG and cost validation if nonempty. |
| `vpn_client_public_cidrs` | set(string) | Required for active VPN | Valid IPv4 CIDRs; empty means no peer ingress and inactive service; no `0.0.0.0/0` default. |
| `vpn_tunnel_cidr` | string | `10.250.0.0/24` | /24; no overlap with VPC/client/on-prem network inputs. |
| `client_network_cidrs` | set(string) | Owner input | Validate tunnel/VPC overlap and document existing conflicts before access. |
| `vpn_peer_inventory_reference` | string or null | Secure configuration artifact reference | No private keys; configuration stage validates unique peer /32s/public keys. |
| `additional_internal_client_cidrs` | set(string) | Empty | Narrow approved private sources only; generates internal ALB rules, never DB rules. |
| `enable_cloudflare` | bool | false until inputs supplied | Production publishing requires true and completed controls. |
| `enable_origin_mtls` | bool | true when Cloudflare production | Cannot be false for production Cloudflare origin; trust artifact required. |
| `publish_origin_routes` | bool | false | Forwarding allowed only after class-specific readiness/authentication attestations. |
| `restricted_test_origin_cidrs` | set(string) | Empty | Required if testing Cloudflare-disabled internet origins; no world-open defaults. |
| `account_security_mode` | string | `existing` | existing/standalone; standalone stack separately owned and approved. |

### 23.2 Compute, storage, sites and database variables

| Variable | Type | Default / selected value | Validation / consumers |
|---|---|---|---|
| `ami_ids_by_role` | map(string) | Required docker/vpn/checkmk AMI IDs | Verify available, trusted owner, x86_64; fixed per release. |
| `compute_profiles` | map(object(instance_type:string,root_gib:number)) | Section 3 profile values | Only approved architecture-compatible types; positive sizes, root minima; documented overrides. |
| `host_allocations` | map(object(role:string,az_key:string,private_ip:string)) | Five hosts in section 14 | Exact five keys; valid usable unique IPs in intended subnet; no EFS or AWS-reserved address collision. |
| `checkmk_data_gib` | number | 50 prod/20 test | At least 20; cannot silently shrink existing EBS. |
| `enable_detailed_monitoring` | bool | prod true/test false | Production true; costed. |
| `ec2_termination_protection` | bool | Profile-derived | Required true prod; planned replacement/destruction requires explicit reviewed change. |
| `release_manifest_reference` | string | Required versioned artifact | Pins AMI provenance, package versions, SHA-256, images, scripts and compatible clients. |
| `sites` | map(object(visibility:string,hostname:string,posix_id:number,database_name:string)) | Three synthetic keys in section 12 | Visibility enum public/secure/internal; unique hostname/POSIX ID; POSIX ID ≥10000; DB name safe identifier; nonempty per required class. |
| `rds_engine_version` | string | `8.4.13` | Supported MySQL8.4 minor; query region/class; major version requires design migration. |
| `rds_instance_class` | string | db.t4g.medium prod/db.t4g.micro test | Orderable capability check; burst thresholds. |
| `rds_multi_az` | bool | prod true/test false | Must true prod. |
| `rds_storage` | object(allocated_gib:number,max_gib:number) | 100/500 prod;20/100 test | Positive supported gp3 sizes; max≥initial and service autoscaling margin; no silent shrink. |
| `rds_backup_retention_days` | number | 14 prod/1 test | Integer1–35; prod minimum14. |
| `rds_deletion_protection` | bool | Profile-derived | Production true. |
| `rds_skip_final_snapshot` | bool | false | Only true for explicitly disposable non-production data. |
| `final_snapshot_release_id` | string | Required for destroy/replacement with final snapshot | Valid deterministic unique suffix; no runtime timestamp churn. |
| `rds_ca_cert_identifier` | string | `rds-ca-rsa2048-g1` | Available regional certificate, expiry/client-bundle check. |
| `enable_rds_enhanced_monitoring` | bool | prod true/test false | Monitoring interval/role nullability validation. |
| `rds_connection_alarm_threshold` | number or null | Obtained at commissioning | Must positive and ≤80% verified max_connections before production alarm activation. |
| `backup_retention` | object(efs_days:number,ec2_days:number,export_days:number,monthly_days:number) | 30/14/30/365 prod;2/2/2/365 test | Positive supported retention; monthly enabled separately; preserve source keys. |
| `enable_monthly_backups` | bool | prod true/test false | Monthly rule enabled only when retained cost accepted. |
| `backup_restore_role_arn` | string | Approved recovery identity | Existing role or optional bootstrap-owned role; no workload principal. |
| `efs_lifecycle_ia_days` | number | 30 | Map to supported enum AFTER_30_DAYS; changes need performance/cost review. |

### 23.3 DNS, certificate, identity and monitoring variables

| Variable | Type | Default / selected value | Validation / consumers |
|---|---|---|---|
| `base_domain` | string or null | Required for full TLS/private DNS deployment | Owned controlled DNS name; no protocol/path; cannot use example.invalid in deployment. |
| `certificate_mode` | string | `external_validated_arn` for AWS-only; managed_dns when Cloudflare configured | Enum in section15; production forbids restricted_test_http. External mode requires all three certs. |
| `certificate_arns` | map(string) | Required in external mode | public/secure/internal ARNs in same account/region; hostname coverage/status ISSUED. |
| `cloudflare_zone_id`, `cloudflare_account_id` | strings or null | Owner input when enabled | Provider-compatible ID format; verify zone ownership matches base domain. |
| `manage_zone_settings` | bool | false | Only true after explicit zone-scope ownership decision. |
| `cloudflare_origin_ipv4_cidrs` | set(string) | Reviewed official range snapshot | Nonempty when enabled; date/hash documented; validate quotas. |
| `origin_ca_bundle_path` | string or null | Required when AOP enabled | Existing reviewed public PEM artifact; reject any PRIVATE KEY marker. |
| `origin_crl_path` | string or null | null | Signed public CRL if revocation configured. |
| `cloudflare_aop_certificate_id` | string or null | External PKI/Cloudflare metadata | Not proof of activation; verification gate required. |
| `cloudflare_access_idp_ids` | set(string) | Required for secure live service | Exactly one approved IdP with MFA enforced upstream while auto-redirect is enabled; multiple IdPs require disabling auto-redirect through a reviewed decision. |
| `secure_access_emails` / `secure_access_group_id` | set(string) / string or null | Owner allowlist or group | At least one approved selector; no Everyone/bypass defaults; exact policy membership reviewed. |
| `cloudflare_team_domain` | string or null | Owner input | Expected JWT issuer and JWKS domain, HTTPS; protect against arbitrary JWKS URL injection. |
| `alert_email` | string or null | Owner input | Confirmed mailbox/subscription required before production; no actual message sent by planning. |
| `monthly_budget_usd` | number or null | Owner input for any deployment | Positive; no implication of hard cap. |
| `log_retention_days` | number | 90 prod/14 test | Valid CloudWatch retention enum; audit separate365. |
| `existing_cloudtrail_arn`, `existing_guardduty_detector_id` | strings or null | Owner/account evidence | Required in existing-security production mode; verify coverage, not only syntactic ARN. |
| `session_manager_preferences_owner` | string | `existing` or shared bootstrap | Single account-region owner; no per-env duplicate document. |

Private keys, database passwords, Cloudflare API tokens and application-secret **values are not Terraform variables**. Environment credential mechanisms and secure runtime secret workflows own them. Examples may include ARNs/IDs marked as required placeholders but must fail validation if left unresolved.

### 23.4 Cross-resource validation and preconditions

Validate CIDR shape, containment and pairwise non-overlap; exact subnet tier/AZ coverage; address uniqueness; trusted AMI ownership; account/region alignment; NAT count by profile; security-rule direction/ports; no public RDS or managed-host IPs except VPN EIP; certificate region and class coverage; Cloudflare dependency completeness; RDS class/engine/storage support; monthly backup/key retention; protected/public hostname separation; site UID/database name uniqueness; metadata policy; required tags; S3/ALB name limits; and existence of alert/recovery inputs for prod.

Use typed variable validation, resource preconditions and Terraform `check` assertions where appropriate. Critical safety conditions must fail plan/CI rather than relying solely on advisory `check` warnings. Service availability, quotas and DNS ownership cannot be proven with regex; query AWS/Cloudflare in preflight. Sensitive metadata values must not be embedded in error messages.

## 24. Output catalogue and downstream handoff

Expose minimal typed outputs. IDs/ARNs/endpoints are generally metadata; mark secret ARNs, internal addresses and peer inventory references sensitive when repository/environment policy requires redaction. Never output secret values, PKI keys or complete user data. A sensitive output is still state content.

| Output | Type / intended consumer |
|---|---|
| `deployment_identity` | Object account_id/region/environment/release_id; operator verification. |
| `vpc_id`, `availability_zone_map` | string and map with AZ name/ID; evidence/integrations. |
| `subnet_ids_by_tier` | Object of public/application/database maps keyed a/b/c. |
| `route_table_ids`, `nat_gateway_ids`, `nat_public_ips`, `s3_endpoint_id` | Named maps/strings; network verification and allowlist evidence. |
| `security_group_ids` | Role-keyed map; configuration and policy checks. |
| `docker_hosts`, `vpn_host`, `checkmk_host` | Objects instance_id/private_ip/AZ/SSM target ID; VPN additionally EIP; no peer keys. |
| `instance_profile_names`, `runtime_role_arns` | Role-keyed metadata maps for operations and permission review. |
| `load_balancers` | Visibility map of ARN, DNS name, zone_id, listener ARN, target group ARN and expected backend port. |
| `certificate_arns`, `certificate_validation_records` | Visibility ARNs and deduplicated DNS tuples when managed; manual DNS handoff only. |
| `origin_trust_store_arn`, `origin_ca_bundle_version_id` | mTLS metadata; null when disabled. |
| `database` | Object identifier/endpoint/address/port/engine_version/subnet group and sensitive managed-master-secret ARN; no password. Only privileged initializer consumes master-secret ARN. |
| `efs` | Object filesystem ID/ARN/DNS name, mount-target IP map and site access-point ID map. |
| `bucket_names`, `bucket_arns` | Purpose maps; no state object content. Bootstrap separately outputs state bucket and key ARN. |
| `application_secret_arns` | Sensitive map for host configuration; secret containers may remain uninitialized. |
| `kms_key_arns`, `backup_vault_arn`, `backup_plan_ids` | Encryption/recovery references. |
| `cloudflare_access` | App ID, audience and expected team issuer; identity metadata for origin validation, not user JWTs. |
| `service_urls`, `private_zone_id` | Public/secure/internal/Checkmk URLs and private zone metadata; label inactive routes clearly. |
| `log_group_names`, `alert_topic_arn`, `dashboard_name`, `budget_name` | Operations handoff; output alert subscription pending/confirmed evidence separately. |
| `feature_status` | Object enabled services/profile and **configuration pending** flags; not computed claims of runtime health. |

Handoff configuration consumes an approved metadata manifest generated from selected outputs, not an unredacted `terraform output -json` archive committed to Git. Avoid `terraform_remote_state` for passing runtime secrets: a reader of an output can often access the whole state object. Prefer direct approved metadata exports or AWS service lookups.

## 25. Verification specification and acceptance evidence

The repository currently contains planning material, not a Terraform implementation. All checks in this section are **future acceptance requirements**. Do not mark them passed when this document is delivered.

### 25.1 Offline source and graph checks

Run formatting, `terraform init -backend=false`, validate and mocked tests independently for bootstrap and each workload root. AWS/Cloudflare providers must be explicitly mocked in offline tests; default `terraform test` can create real resources and is not automatically safe. Run TFLint with pinned AWS rules, Trivy configuration scanning and a secret scanner. Pin CI tool/action versions or commit SHAs, record checksums, and document accepted findings with justification/expiry. Provider schema validation proves argument shape, not regional service feasibility.

| Test group | Assertions / expected failure cases |
|---|---|
| Identity and naming | Wrong account/region rejected; required tags present; name length/hash stable; duplicate full-name shortening impossible in selected graph; prod without CostCenter rejected. |
| Network topology | One VPC, nine /24s, three distinct AZs, correct CIDRs/tiers/associations; malformed, overlapping/out-of-VPC CIDRs and reserved/conflicting IPs rejected. |
| Routes | Public IGW default; app same-AZ NAT prod/C-NAT test; DB local only; S3 endpoint on exactly selected tables; no accidental VPN or IPv6 default. |
| Default controls | Default SG empty; adopted main table quarantined; default NACL selected rules explicit; all nine subnets attached as intended. No claim that NACL is deny-all. |
| Security groups | Exactly allowed source/destination ports; no internet SSH/DB/NFS/Checkmk/Docker API; public8080/secure8081/internal8082; no public listener can reach secure port. |
| Compute | Five hosts/three roles; only VPN EIP; no auto public IP; IMDSv2/hop1; encrypted gp3; no keypair; sizing/credit profile; static replacement conflict accounted for. |
| Data | RDS private+TLS; prod Multi-AZ/deletion/retention; engine family consistent; EFS Regional+three targets+access points; secret values absent from configuration/state fixtures. |
| S3/KMS/IAM | Public block, versioning, expected key by purpose; ALB log SSE-S3 exception; least-privilege secret/state scopes; no runtime master/state access; key policy service access present. |
| ALBs/DNS | Three 3-AZ schemes, three cert classes, default403, nine attachments, mTLS for published Cloudflare prod origins, disjoint hostname routing, internal record private only. |
| Feature gating | Missing cert/domain/IdP/CA/alert inputs fail affected prod gate; disabled Cloudflare has no credential-requiring resources; no implicit test HTTP downgrade. |
| Backups/observability | Exact resource selection, matching Project/Environment/BackupPolicy; two nonduplicated plans; native RDS backup; no EFS default duplicate; alarm dimensions/retention/actions verified. |
| Negative production cases | Single NAT, DB Single-AZ, world-open origin, missing auth, disabled encryption, skipped final snapshot, missing alerts/security ownership fail CI. |

Scanner exceptions need narrow scope: default allow-all NACL is selected; backend HTTP is selected; ALB logs use SSE-S3 for service compatibility; HTTPS egress 0.0.0.0/0 is explicit; Checkmk/VPN are singletons. Do not disable whole scanner categories or describe these as deployed mitigations before verification.

Test cloud-init/templates using YAML/shell syntax validation and idempotency checks on a disposable local VM or approved instance. Check that scripts do not log secrets, mounts block application startup, volume formatting detects existing data, attachment races are handled, and firewall rules survive reboot. Tests that only compare a constant to itself do not establish system behavior.

### 25.2 AWS preflight and real plan

Read-only preflight must record caller account/role, eu-west-1 AZ map, vCPU/EIP/NAT/ALB/SG-rule quotas, available AMIs, orderable RDS engine/class/storage/Multi-AZ options, current RDS CA, required service-linked roles, SSM endpoint access, DNS ownership, Cloudflare capabilities and existing account controls. A new account may need quota increases. No availability claim based solely on a public documentation table.

Generate a saved plan with approved environment values only after credentials/backends are configured. Inspect plan JSON in protected temporary storage for assertions/cost checks; redact summaries for interview sharing. Verify resource inventory, exact expected account, no unwanted deletions/replacements, no default-public services, no unexpected backend keys and no account-global changes. Capture tool versions, Git commit and plan checksum. Never post full plan JSON or state in CI logs.

### 25.3 Optional live functional and failure tests

| Area | Positive test | Denial/failure test and required evidence |
|---|---|---|
| VPC/NAT | Each private host reaches approved HTTPS destination; S3 uses endpoint route | DB route table has no default; test NAT C failure impact recorded without production claims. |
| SSM | All five managed nodes online; audited shell session | Public SSH fails; unauthorized operator/remote-host document denied; forwarding content logging limitation recorded. |
| Bootstrap/OS | Cloud-init completed, agents active, manifest matches, disks encrypted | Missing secret or EFS mount keeps app unready; no local-upload fallback; reboot recovers services. |
| Containers | All expected replicas/images and ports; correct site rendering | Port8080 rejects protected host/routes; no public Docker socket; direct host access denied. |
| EFS | TLS/IAM mounts, per-site file test across hosts | Wrong role/access point and plaintext/anonymous mount denied; absent mount fails closed. |
| RDS | Verified TLS, restricted site user, migration/connectivity | Public/VPN direct DB denied; site user cannot access another schema or perform admin operations. |
| ALBs | Correct certificates, target health and vhost routing | Unknown host403; secure name through public ALB rejected; all three healthy groups don't substitute for application checks. |
| Cloudflare | Proxied public site and authorized secure login | Missing/wrong audience/expired JWT denied at origin; direct origin without dedicated mTLS denied; other-zone/spoofed Host does not bypass. |
| Internal DNS/VPN | Authorized peer resolves private names and reaches internal/Checkmk443 | Invalid/revoked peer fails; DB/metadata/808x forwarding denied; no open DNS recursion; routes remain split tunnel. |
| Checkmk | Real agent/AWS checks show expected hosts/metrics | Stop a synthetic service/agent and observe alert/recovery; server outage caught by independent heartbeat/EC2 alarms. |
| Logs/alerts | Flow record, ALB log object, cloud-init/agent log and confirmed SNS test | Secret-redaction test; service delivery fails visibly if policy misconfigured; pending subscription reported incomplete. |
| Backup | Manual approved job/recovery point and site export success | Restore to isolated resources, measure time/integrity; simulate stale marker/no job to test freshness alarms. |
| Resilience | Drain one Docker host, verify remaining replicas and uploads | RDS failover only with explicit exercise approval; capture interruption/reconnect, do not claim zero downtime. |
| Teardown | Reviewed disposable removal and residual inventory | Snapshots, recovery points, versions, retained volumes/EIPs/logs/keys checked; no shared/prod resource included. |

Use only synthetic data. Destructive/failure exercises need separate approved scope; ordinary configuration or document approval does not authorize them. Record `PASS`, `FAIL`, `NOT RUN` or `BLOCKED` per test with date, command/probe, environment/release, result and evidence location. Interview evidence must distinguish mocked/static checks, AWS plan validation, provisioned infrastructure and working applications.

References: [Terraform testing](https://developer.hashicorp.com/terraform/language/tests), [provider mocks](https://developer.hashicorp.com/terraform/language/tests/mocking), [input validation](https://developer.hashicorp.com/terraform/language/expressions/custom-conditions), [Terraform CLI validation](https://developer.hashicorp.com/terraform/cli/commands/validate), [AWS Service Quotas](https://docs.aws.amazon.com/servicequotas/latest/userguide/intro.html).

## 26. Deployment, change, rollback, costs and teardown

### 26.1 Before implementation and before billable deployment

1. Accept this specification and record design decisions/remaining owner inputs in ADRs. Preserve the diagram and master plan; this document supersedes the master's generic “next action” only for the requested detailed planning step.
2. Implement bootstrap/modules/roots in section2 order on the current suitable checkout. Preserve unrelated/untracked files. Commit small reviewable changes and lockfiles; no automatic push/publication is implied.
3. Harden `.gitignore` before generating plans or credentials: `.terraform/`, `*.tfstate*`, `*.tfplan`, `*.plan`, crash logs, real `*.tfvars`, backend credentials, `.env*`, private keys, downloaded secret artifacts and local plan JSON. Continue tracking `.terraform.lock.hcl`, sanitized `*.tfvars.example` and partial backend examples. Existing `.gitignore` does not yet ignore every saved-plan/private-key form.
4. Run offline gates; resolve findings and review source/module documentation. Keep architecture decisions and source evidence understandable to interviewers.
5. **Separate live-deployment gate from the master plan:** before billable create, explicitly confirm sandbox account ID, region, credential profile, domain scope, estimated cost ceiling, runtime duration and teardown owner. No live deployment is needed for the interview submission. Planning authorization does not authorize cloud spending or DNS publication.

Cost estimate must use current [AWS Pricing Calculator](https://calculator.aws/) and current Cloudflare entitlements, not reuse the master's illustrative hourly allowances as a quote. Include five EC2 instances, six EBS volumes, 1/3 NAT gateway hours+bytes, three ALB hours+LCUs, public IPv4 addresses (VPN/NAT **and** ALB service addresses), RDS compute/standby/storage/backups/monitoring, EFS storage/Elastic throughput/IA access, S3 requests+versions+retention, KMS requests/keys, Secrets Manager, CloudWatch metrics/logs/dashboard/alarms, AWS Backup, DNS/private zone, internet/cross-AZ transfer, optional endpoints, licences and taxes. Include retained-data charges after compute teardown. Cost alerts are not enforcement of the ceiling.

### 26.2 Controlled initial deployment

1. Log in with approved SSO/temporary credentials; inspect caller identity and quotas. Never print credential files. Complete preflight evidence and resolve blocked inputs.
2. Initialize bootstrap locally, validate, plan, inspect and apply the reviewed bootstrap plan only under approved deployment scope. Protect local state; migrate into remote bootstrap key with backup/reconciliation. Verify versioning, key policy and native locking, including a controlled concurrent-lock test.
3. Initialize environment root with partial backend config; use `init -migrate-state` only when intentionally migrating known local state. `-reconfigure` is for selecting a known backend, not losing track of existing state.
4. Plan the complete environment with non-secret reviewed inputs; inspect exact plan and checksum. Separate any shared-security/account-setting changes from workload changes. Avoid general `-target` or `-refresh=false` workflows.
5. Apply that saved plan with the approved role. Capture resource creation status and Terraform outputs in protected storage. On partial failure inspect state/AWS errors, resolve root cause, then generate a new reviewed plan. Do not rerun an old plan after state has changed.
6. Initialize secrets externally; configure/mount/data-initialize hosts; run migrations once under restricted initializer permissions; enable actual services. Verify EFS targets/SSM and Checkmk volume before configuration. No local-exec SSH, private keys or `remote-exec` provisioners.
7. Complete certificates/AOP/Access and class-specific security/readiness gates, enable forwarding rules, then publish approved DNS. Do not call targets “healthy” until real probes confirm health.
8. Enable/confirm backup jobs, telemetry publishers and subscriptions; run selected live checks and a sample restore. Record any feature unavailable due to domain/licence/input constraints as NOT RUN.
9. Generate module docs, deployment evidence, cost/residual-resource report and interview walkthrough. Do not publish secrets, state or saved plans.

Future PowerShell runbooks should wrap `terraform fmt`, `init`, `validate`, lint, scans, explicitly mocked `test`, reviewed `plan -out`, `show` and `apply` of that plan; they must check exit codes and identity before mutations. No deploy script may auto-approve every plan or silently disable protections to make apply succeed.

### 26.3 Changes and rollback

Deploy image/configuration changes independently from infrastructure where possible. Pin known-good artifacts and retain previous versions. One-host-at-a-time Docker replacement requires target drain, bounded connection wait, verified EFS/secret retrieval, health probes and re-registration before the next host. Static addresses mean replacement is destructive for that host; spare capacity and three replicas must be tested, not assumed.

Rollback a stateless release by restoring known-good image/configuration and coordinating schema compatibility. Rollback infrastructure by reverting configuration and reviewing a **new** plan; an old state snapshot or saved plan is not a rollback mechanism. RDS engine changes/storage growth may be irreversible in place; use supported upgrade/restore/blue-green strategy separately. Restoring a DB/EFS backup creates new resources and may lose newer data; obtain cutover/reconciliation approval and update Terraform ownership before traffic switch. EFS/RDS/S3 data deletion or KMS deletion is never treated as a routine revert.

Do not use broad lifecycle `ignore_changes` to suppress drift. Narrow exceptions may cover externally filled secret values (not Terraform-owned versions), service-managed autoscaling storage behavior and AWS-owned policy fields only when documented. Terraform lifecycle `prevent_destroy` cannot be made conditional with an ordinary variable; use static bootstrap guards and reviewed production policy gates, not invalid `prevent_destroy = var.environment == ...` code. EFS/S3 retention is enforced through IAM/review/CI policies in the initial baseline; RDS/ALB/EC2 additionally have service-specific protections described above.

### 26.4 Disposable teardown and retained-resource ownership

1. Review exact environment/account and classify all data/resources as disposable, retained or shared. Generate and inspect a destroy plan; obtain the scoped destruction approval required by the master plan. Never disable production protections implicitly.
2. Remove only this environment's leaf DNS/Access records and routes under approved scope; preserve ACM validation records needed by retained certs. Keep shared zone settings/IdP untouched. Revoke temporary VPN peers/AOP secrets outside Terraform when no longer needed.
3. Disable test protections only by explicit reviewed configuration; wait for in-flight backups/configuration to finish. Decide RDS final snapshot/automated-backup retention using the actual data policy.
4. Destroy workloads in dependency order via Terraform. Manually empty **only verified disposable** versioned buckets/recovery points under their owning workflow when necessary; `force_destroy` stays false. Audit inventories before any recursive local cleanup.
5. Verify stopped/terminated EC2, root and retained Checkmk data volumes, all NAT/EIPs, ALBs, RDS/final/manual/automated snapshots, EFS/access points, AWS Backup recovery points/vault, S3 object versions/delete markers, Secrets Manager pending deletions, log groups, optional endpoints/private DNS and KMS pending-deletion timers. Some retained artifacts remain billable after Terraform says destroy complete.
6. Keep state/backend and shared security controls until workload removal and recovery-retention decisions are verified. Bootstrap teardown is separate and occurs only if explicitly requested. Never delete state to make teardown appear complete.
7. Record actual residual resources/cost owners; check billing after usage reporting catches up. Reconcile drift/import ownership for intentionally retained resources before future reuse.

## 27. Owner inputs, decision register and implementation completion gate

### 27.1 Selected engineering decisions

| Decision | Selected baseline | Consequence / reason |
|---|---|---|
| Region/topology | eu-west-1, nine original CIDRs, three AZs | Faithful to master; account-relative AZ mapping required. |
| NAT | Three zonal prod / one C test | Production zonal egress resilience versus explicitly reduced test cost. |
| Checkmk placement | Private app C `10.0.6.30` | Functional outbound path without public exposure; documented diagram deviation. |
| NACL | Managed allow-all default | SGs enforce access; avoid incomplete stateless rules. |
| Compute | Five fixed Ubuntu24.04 AMD64 hosts, selected T3 sizes | Assignment fidelity; no scheduler/autoscaling promise. |
| Visibility | Three ALBs and ports8080/8081/8082 | Distinct traffic paths and backend authorization boundaries. |
| Origin/authentication | Dedicated AOP mTLS + secure Access JWT verification | Zone-origin identity plus independent user/application authorization. |
| VPN | WireGuard split tunnel, controlled SNAT | Simple unambiguous return path and destination rules; peer identity retained at VPN/application layers. |
| Storage/DB | Regional EFS, per-site access points; one MySQL8.4 Multi-AZ instance | Shared uploads and managed DB failover; standby not a reader. |
| Monitoring | Private Checkmk + independent CloudWatch/SNS | Checkmk singleton does not suppress platform failure alerts. |
| State/secrets | S3 native lock/KMS/versioning; secrets initialized outside state | Repeatable IaC without private-key/password leakage. |
| Workload backup | Native RDS PITR + explicit EFS/EC2 plans + logical exports | Separate recovery mechanisms with explicit consistency/restore boundaries. |

### 27.2 Inputs required before the affected deployment

| Input / confirmation | Owner | Effect if unavailable |
|---|---|---|
| AWS account, role/SSO profile, AZ mapping, quota and security-control ownership | Account administrator | No AWS plan/apply; static/mocked implementation can continue. |
| Actual AMI IDs, pinned package/image manifest and tested provider schemas | Implementation engineer | No compute release; do not invent IDs or claim package compatibility. |
| Workload demand, tenant trust model and accepted initial sizes | Platform owner | Synthetic sizing only; no customer capacity claim. |
| Domain, zone/account IDs, DNS edit scope, validated certs | DNS owner | No real published/TLS endpoint; do not silently deploy public HTTP. |
| AOP entitlement, dedicated CA artifact and external client-certificate upload | DNS/security owner | No production Cloudflare origin activation. |
| IdP IDs, MFA policy, approved secure users/groups, team issuer | Identity owner | Protected forwarding remains disabled. |
| VPN client networks, approved source CIDRs and peer public-key inventory | Network administrator | VPN may exist with no active access; no guessed peers. |
| Checkmk edition/package acceptance and alert recipients | Monitoring owner | Installation/alert coverage incomplete until verified. |
| Data retention, RPO/RTO, restore role and exercise scope | Data/platform owner | Proposed schedules only; production recovery sign-off absent. |
| CostCenter, budget amount, sandbox duration and teardown owner | Budget owner | No billable deployment authorization. |

These are external facts/business approvals, not unresolved choices about how to write the Terraform resources. Implement validation and explicit disabled/pending states rather than replacing missing values with insecure defaults.

### 27.3 Definition of complete Terraform implementation

- All baseline resources and arguments in this document are represented in modules with documented optional branches and stable identities.
- Typed inputs, validation, outputs, naming/tagging, state controls and dependency graph match the specification; no circular modules or unsupported/deprecated argument substitutions.
- Root tool/provider versions and checksums are pinned; offline format/validate/lint/security/mocked tests pass with actual recorded evidence.
- Runtime configuration artifacts are versioned, secret-safe, idempotent and separately tested; data initialization, JWT validation, VPN and Checkmk are not represented as complete merely because EC2 exists.
- README, ADRs, module READMEs, configuration examples, cost estimate, deploy/rollback/destroy runbooks and validation evidence are reviewable by an interviewer without private account access.
- Live AWS/DNS deployment remains optional. If performed, approved scope, actual plan, smoke/restore results and residual-resource cleanup evidence are recorded. Untested features remain labelled.

## 28. Official reference index and maintenance notes

Subsystem sections contain direct resource links beside their arguments; this index supplies the owning service/engineering documentation. AWS service behavior and Terraform schema are separate authorities: AWS defines service constraints, the pinned provider defines available argument names, and this specification selects project values. No community tutorial is an authority for security or resource compatibility.

| Area | AWS / vendor documentation | Terraform documentation |
|---|---|---|
| Core and state | [AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/overview.html), [S3 security](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html) | [Terraform language](https://developer.hashicorp.com/terraform/language), [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3), [provider requirements](https://developer.hashicorp.com/terraform/language/providers/requirements), [lockfile](https://developer.hashicorp.com/terraform/language/files/dependency-lock) |
| Provider/release schema | [AWS API reference catalogue](https://docs.aws.amazon.com/) | [AWS6.73.0](https://registry.terraform.io/providers/hashicorp/aws/6.73.0/docs), [Cloudflare5.29.0](https://registry.terraform.io/providers/cloudflare/cloudflare/5.29.0/docs), [HashiCorp releases](https://releases.hashicorp.com/terraform/) |
| VPC/network | [VPC guide](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html), [route tables](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html), [NACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html), [PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html) | [AZ data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones), [VPC resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) and links in sections6–8 |
| Compute/OS | [EC2 guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/concepts.html), [EBS](https://docs.aws.amazon.com/ebs/latest/userguide/what-is-ebs.html), [Ubuntu AWS](https://documentation.ubuntu.com/aws/) | [EC2 instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) and section14 |
| Load balancing/certificates | [ALB](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html), [ACM](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html), [Route53 private DNS](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html) | [ALB](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) and sections15–16 |
| RDS | [RDS guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html), [MySQL version support](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/MySQL.Concepts.VersionMgmt.html) | [DB instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) and section13 |
| EFS | [EFS guide](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html) | [EFS filesystem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) and section12 |
| IAM/secrets | [IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction.html), [Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html) | [IAM policy document data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document), [caller identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity), [OIDC provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider), [region data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region), [partition data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition), [ACM data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/acm_certificate) |
| Backup | [AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) | Resource links in section20; encryption and retention must follow actual service support. |
| Monitoring/audit | [CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html), [EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html), [CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html) | Resource links in section21. |
| VPN/management | [WireGuard](https://www.wireguard.com/), [Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html), [Checkmk](https://docs.checkmk.com/latest/en/) | EC2/SG/SSM resources in sections14,18,19; no invented WireGuard AWS managed-resource type. |
| Cloudflare | [Terraform integration](https://developers.cloudflare.com/terraform/), [ALB AOP](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/aws-alb-integration/), [Access JWT verification](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/) | v5 resource links in section17. |
| Tests and rollout | [AWS Well-Architected reliability](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html), [pricing calculator](https://calculator.aws/) | [Terraform tests](https://developer.hashicorp.com/terraform/language/tests), [plan](https://developer.hashicorp.com/terraform/cli/commands/plan), [apply](https://developer.hashicorp.com/terraform/cli/commands/apply) |

Documentation links with `/latest/` are convenient navigation links, not permission to upgrade the locked provider. Before implementation, compare them against the selected version's schema and record any differences as an ADR/specification correction. Before each release, refresh regional availability, supported OS/packages, certificate/engine lifecycle and pricing evidence. Preserve a dated validation manifest rather than describing documentation research as an AWS deployment test.

**Document completion record:** This specification defines the full selected resource/configuration design and the implementation, operational and review boundaries. Owner-specific facts remain explicit inputs. No Terraform source, cloud-init, cloud resources, DNS changes, test executions or production readiness are asserted by the document itself.
