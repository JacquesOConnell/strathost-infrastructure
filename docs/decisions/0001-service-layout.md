# 1. Service modules and server scripts

**Date:** 25 November 2026. **Status:** Selected implementation structure.

## Decision

I use direct service modules under `modules/` and keep environment roots short. I do not add the optional `modules/platform` wrapper proposed in the technical plan. This follows the requirement to keep the code straightforward and separate services such as networking, storage and EC2.

| Responsibility | Selected location |
|---|---|
| VPC, subnets, NAT, routing and endpoint resources | `modules/networking` |
| S3, EFS and their storage policies | `modules/storage` |
| Instances and EBS attachments | `modules/ec2` |
| RDS instance and database subnet group | `modules/database` |
| ALBs, listeners, target groups and attachments | `modules/load-balancing` |
| IAM roles, instance profiles, policies and secret containers | `modules/iam` |
| Dedicated security groups and traffic rules | `modules/security` |
| Workload KMS keys and aliases | `modules/encryption` |
| Checkmk integration and diagnostic flow logs | `modules/monitoring` |
| Backup schedules and recovery resources | `modules/backup` |
| Optional DNS and access integration | `modules/cloudflare` |
| Operating-system and service setup | `scripts/docker`, `scripts/wordpress`, `scripts/checkmk`, `scripts/vpn` |

All listed service modules now contain resources. Private DNS is additionally separated under modules/dns. One short composition root at the repository root selects its environment through explicit tfvars/backend inputs; the optional Cloudflare root/state stays separate. This avoids duplicating all module calls in test and production folders.

## Reasons and consequences

This groups resources by the service being reviewed and avoids forwarding variables through an extra wrapper. Related resources use separate descriptive files inside their service module. Inputs and outputs connect modules through the environment root; state remains one workload state per environment and a separate bootstrap state.

The S3 endpoint policy is assembled at the environment root rather than inside networking. The root can reference approved identities and bucket paths without making networking own workload permissions. Dedicated security-group shells and rules will be managed by security rather than mixed into EC2 resources. This preserves the plan's cycle-avoidance and ownership rules.

Server scripts configure software after infrastructure exists. They are reviewed and documented separately, and Terraform receives no credential values. The current user-data script starts only SSM. Executable server scripts are present and are run through the separately controlled configuration stage; Local WordPress/PHP container integration has now been tested; Ubuntu/systemd and cloud-service acceptance remain pending.

The original diagram and master plan remain unchanged. This record supersedes only the proposed folder/composition arrangement, not the architecture, security requirements, resource counts or deployment approval boundary.
