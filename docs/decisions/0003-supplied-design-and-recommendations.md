# 3. Supplied architecture and separate recommendations

**Date:** 25 November 2026. **Status:** Selected scope.

I implement the supplied diagram and keep recommendations separate. Docker01, Docker02 and Docker03 remain fixed EC2 hosts; no Auto Scaling Group, ECS or Kubernetes is added. VPN and Checkmk remain single servers.

The diagram baseline contains one NAT in C. Per-AZ NAT remains an optional improvement rather than a mandatory production-label rule. Custom origin mTLS and its CA bucket are optional engineering proposals, not requirements shown in the diagram. They must not be forced simply by setting `environment = "prod"`.

The diagram places Checkmk in public C. That is the assignment baseline for the upcoming EC2 module; private application-C placement from the earlier technical proposal is recorded as a recommendation instead. Public subnet placement does not require public dashboard access. An outbound IPv4 path and restricted VPN/SSM administration must be configured explicitly.

AWS semantics still apply: the IGW belongs to the VPC, S3 is regional, ALBs cover multiple subnets, the three EFS symbols represent Regional storage access, and RDS manages its standby. These are implementation interpretations of the diagram rather than extra application services.

The original diagram, master plan and pre-development specification remain as source documents. This scope decision supersedes their optional expansion proposals where noted above. The [recommendations](../RECOMMENDATIONS.md) explain potential changes, benefits, costs and prerequisites without presenting them as delivered infrastructure.

## Subsequent implementation details

Checkmk is the monitoring platform. Native CloudWatch metric reads and bounded RDS/VPC diagnostic logs support it; no separate CloudWatch alarm/dashboard/agent or SNS alert stack is deployed. The unused alerts KMS key was removed, leaving seven workload keys. External Checkmk availability monitoring remains a recommendation.

Checkmk's fixed private address 10.0.3.30 and intentional public IPv4 are selected engineering values, not labels from the diagram. They make outbound SSM/packages work in public C while the dashboard stays private through security groups. The three fixed Docker addresses and EFS mount-target addresses are also selected allocations within the supplied subnet CIDRs.

The RDS primary/standby is retained as Multi-AZ in test as well as production; the earlier reduced Single-AZ test proposal is superseded. Certificate issuance, approved roles/identities and immutable release artifacts remain explicit owner-supplied inputs. Private DNS and diagnostic logs implement the plan's supporting configuration without adding extra application workloads.
