# Security groups

I implemented the traffic contract from section 8 of the [technical plan](../../TERRAFORM-IMPLEMENTATION-PLAN.md) using eight dedicated security groups and standalone ingress/egress rules. Security groups are separate from EC2, RDS and EFS resources, so the traffic rules can be reviewed without reading server definitions. Schema validation and four mocked test runs pass with AWS provider 6.73.0; live traffic tests have not run.

## What I used and why

| Boundary | Configuration and reason |
|---|---|
| Public and secure ALBs | HTTPS 443 only from the supplied Cloudflare snapshot, or explicitly supplied non-production test clients |
| Cloudflare in production | Required by validation; CIDRs are reviewed input, not fetched automatically during a plan |
| Separate application paths | Public, protected and internal ALBs use 8080, 8081 and 8082 respectively, preventing a shared listener from exposing a protected site through the public ALB |
| MySQL | Docker security group only, TCP 3306; no VPN or monitoring-server database ingress |
| EFS | Docker security group only, TCP 2049; encryption and access-point controls are enforced separately by EFS and the mount helper |
| WireGuard | UDP 51820 from explicit client IPv4 CIDRs; a `/0` input is rejected |
| VPN private access | Internal ALB and Checkmk HTTPS accept the fixed SNAT address `10.0.1.10/32` |
| Checkmk agent pull | Checkmk group to Docker/VPN groups on TCP 6556; self-monitoring remains local |
| Agent registration | Docker/VPN groups to Checkmk on TCP 443 and 8000 |
| Checkmk synthetic checks | Checkmk group to internal ALB on HTTPS |
| Managed outbound HTTPS | Docker, VPN and Checkmk groups may initiate TCP 443 to IPv4 destinations for packages, AWS APIs, registries and approved integrations |

Every application/data/agent flow has the corresponding source egress rule. The managed-host HTTPS exception already covers registration on 443 and private HTTPS, so I did not add redundant HTTPS egress rules. Return traffic uses security-group connection tracking rather than broad ephemeral-port ingress.

The broad outbound HTTPS rule is an explicit exception from the plan, not destination filtering. It also covers S3 prefix-list destinations; a redundant S3-specific egress rule was omitted. VPN host forwarding rules must still limit which private destinations peers can reach. Security groups do not inspect HTTPS identity, JWTs or mTLS, so origin authentication and protected application routing remain separate requirements.

## Inputs and handoff

The module accepts the environment, VPC, cost center, Cloudflare mode and CIDRs, approved origin-test CIDRs and approved VPN client CIDRs. The optional additional tags cannot override mandatory labels. Each group and service-to-service rule has a direct resource name, for example `aws_security_group.docker_hosts` and `aws_vpc_security_group_ingress_rule.mysql_from_docker`.

It outputs a simple `security_group_ids` map. Consumers select the matching group rather than the VPC default group. The composition root must finish security rules before starting server configuration; the output map no longer carries a long list of readiness dependencies. Cloudflare and client CIDR rules still use `for_each` because every entry receives the same rule.

The versioned range snapshot is [config/cloudflare-ipv4.json](../../config/cloudflare-ipv4.json), retrieved from Cloudflare on 25 November 2026. The environment root must load and pass it explicitly; the module does not retrieve internet data during planning. Recheck the official list before deployment and review any committed update. The test fixture uses a single range to test selection behaviour, not to represent Cloudflare's complete network.

## Verification limits

Four mocked plan runs cover separated proxy ports, Docker-only data paths, Checkmk sources, SNAT address, rejection of world-open VPN input, rejection of production without Cloudflare, and origin-range selection. These checks do not validate an authenticated session or a live packet path. Before acceptance, test permitted and denied routes, verify SG quotas, configure host firewalls and prove that public routing cannot reach protected sites. IPv6 and interface endpoint groups are outside this baseline.

References: [AWS security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html), [Cloudflare ranges](https://www.cloudflare.com/ips-v4), [Terraform ingress rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule), [Terraform egress rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule), [Checkmk Linux agent](https://docs.checkmk.com/latest/en/agent_linux.html).
