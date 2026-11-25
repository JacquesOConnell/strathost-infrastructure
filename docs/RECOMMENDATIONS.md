# StratHost recommendations

**Status:** Recommendations for discussion, separate from the supplied architecture. **Reviewed:** 25 November 2026.

I would implement the supplied design first and use the following recommendations to discuss reliability, security and operating cost. A recommendation is not a claim that the feature has been deployed or that the current design has passed its acceptance tests.

## Supplied baseline

The diagram shows three fixed Docker hosts across three AZs, public/secure/internal load balancers, shared WordPress EFS, a primary/standby database, one NAT gateway, an internet gateway, an S3 backup bucket, Cloudflare, and single VPN and Checkmk servers. AWS supporting resources such as IAM roles, routes, security groups, certificates and encryption are implementation details needed to operate that design.

I retain fixed EC2 hosts in the code. VPN and Checkmk remain single servers. The three EFS symbols are implemented as one Regional filesystem with a mount target in each application AZ. The database primary and standby are one RDS Multi-AZ DB instance deployment. ALBs span multiple subnets as required by AWS rather than existing in only the single AZ where each icon is drawn.

## Proposed architecture improvements

| Recommendation | Why I would consider it | Tradeoff and prerequisites |
|---|---|---|
| Auto Scaling for the Docker fleet | An Auto Scaling Group could maintain three healthy hosts and replace failed instances automatically. A fixed desired/minimum/maximum of three would provide replacement without introducing demand-based scaling. | Requires a launch template, repeatable host/container setup, EFS mounts, secrets retrieval, target registration and startup health checks. Fixed instance IPs/names would need to change. A backup job must not depend on a permanently named Docker01. Multi-AZ balancing does not guarantee one host in every AZ during an outage. |
| One NAT gateway per AZ | The supplied single NAT is an outbound dependency on its AZ. Same-AZ NAT routing lets other application AZs retain internet egress if that zone is unavailable. | Adds NAT gateways and public IPv4 addresses with recurring charges. Price the selected region and traffic first. This improves egress resilience; it does not replace application failover or remove every dependency. |
| Private placement for Checkmk | Checkmk could run in a private subnet with NAT or reviewed endpoints for outbound management traffic, retaining private VPN/SSM administration. | This changes its public-C placement in the diagram. It needs a proven outbound path for AWS APIs and package downloads; moving the instance without changing routing would break operations. It can remain a single server. |
| Automated delivery through an approved CI workflow | Formatting, validation, tests and reviewed plans can run consistently before infrastructure changes are accepted. | Use narrowly scoped short-lived role credentials, protected deployment environments and an approved apply step. Untrusted pull requests must not receive deployment credentials. This requires agreement on repository/account ownership. |

AWS documents [ASG health replacement and AZ distribution](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-groups.html), [the single-NAT AZ dependency](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html), [private-subnet routing](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario2.html) and [workload IAM roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html). No cost saving or availability percentage is assumed without measurement and pricing.

## Verification priorities

These are ways to demonstrate the supplied setup works; they are not additional AWS services.

1. **Prove application failover.** Drain or stop one Docker host during an approved test. Confirm every site remains available through the correct ALB and that protected/internal routes remain restricted. Separately test database failover and client reconnection. Record actual recovery time and failed requests.
2. **Prove recovery from backups.** Restore the database and required files into an isolated test environment and verify the recovered site. Agree acceptable recovery time and data loss with the owner. A successful backup job or EFS tag alone does not demonstrate recoverability.
3. **Measure capacity before increasing it.** Capture CPU credits, memory, PHP worker saturation, ALB latency/errors, EFS activity and database connections under representative load. Initial instance sizes are planning values. Burstable hosts need particular attention under sustained load.
4. **Verify the security boundary.** Test the intended VPN/SSM administration paths, denied direct database/NFS access, protected-site authentication, certificate validation and least-privilege role access. Encryption settings and green Terraform tests do not prove these runtime controls.

These priorities follow AWS guidance on [testing reliability](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/test-reliability.html), [testing backup recovery](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_backing_up_data_recovery.html) and [burstable EC2 performance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances.html). The [Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html) is a review aid, not a certification of this implementation.

## Suggested order

First deliver and validate the supplied topology. Next demonstrate access restrictions, application failover and backup recovery. Then review the ASG and NAT proposals against operational needs, implementation effort and measured costs. I would retain VPN and Checkmk as single instances unless their availability requirements change.

## Architecture observations for discussion

**Three hosts need spare capacity, not just separate AZs.** I would test whether the remaining two hosts can serve the required traffic after losing one. Spreading an already saturated workload across three AZs would not establish that capacity. I would also monitor database connections before introducing elastic compute scaling, because more PHP workers can increase database pressure.

**Shared storage shares mistakes as well as files.** EFS lets every replica see the same uploads, but an unwanted file change can be visible to every replica too. I would keep application code in reviewed images and test recovery of compatible database and file versions. Availability and recoverability solve different problems.

**A secure load balancer needs a secure application path.** I would prove that a protected site's hostname/path cannot be served by the public listener or another proxy route. HTTPS protects transport; it does not establish user authorization. I would include an attempted direct-origin bypass in the acceptance evidence.

These are questions and proposed tests, not measured findings. They show where I would investigate the design before making capacity, recovery or access-control claims.
