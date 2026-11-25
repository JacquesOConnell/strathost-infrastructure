# Checkmk monitoring

I use Checkmk for service state, dashboards and notifications. This module attaches AWS inventory and metric-read permissions to the Checkmk EC2 role and exports a non-secret five-host inventory. CloudWatch's metric API supplies native AWS measurements; no parallel CloudWatch alarm, dashboard, SNS topic or CloudWatch agent is created.

The [configuration runbook](../../scripts/checkmk/README.md) covers the Community server, encrypted persistent disk, TLS agents, AWS integration, discovery and acceptance. The separate Ultimate trial lab does not define production licensing. Community automatic host creation is not assumed.

| Area | Collection |
|---|---|
| CPU, memory, filesystems, interfaces, systemd | Linux agents |
| EC2, EBS, RDS, S3 and ALB | AWS special agent with instance-profile credentials |
| EFS access | Docker-host local mount checks; do not assume native EFS integration |
| Backup jobs and freshness | Custom local check for completed recovery points and latest backup-job status |
| WordPress and TLS | HTTPS synthetic checks plus ALB target health |
| VPN | Host checks and a real connected-peer test |
| Containers | Version-matched Docker plugin after Python dependency/socket review |

Wildcard resources are used where inventory/metric APIs require discovery. Regional calls target eu-west-1. S3 discovery is global; bucket metadata is restricted to this account. The monitor lists export timestamps without reading backup contents. Billing, classic ELB and service-limit checks are disabled. The selected EC2/EBS/S3/RDS/ELBv2 non-limit calls were reviewed against the [official v2.5.0p21 AWS special-agent source](https://github.com/Checkmk/checkmk/blob/v2.5.0p21/cmk/plugins/aws/special_agent/agent_aws.py). Live authorization and upgrade-time permission review remain required.

Schema validation and one mocked inventory test pass. These do not establish IAM authorization. Diagnostic VPC Flow Logs use a dedicated service role and encrypted log group with 14/90-day retention; they are not a second alerting platform. Real polling, log delivery, notifications, failure detection and restore tests remain pending. A single Checkmk server cannot report its own total loss; external availability monitoring is a recommendation.

References: [AWS integration](https://docs.checkmk.com/latest/en/monitoring_aws.html), [TLS agents](https://docs.checkmk.com/latest/en/agent_linux.html), [local checks](https://docs.checkmk.com/latest/en/localchecks.html), [self-monitoring](https://docs.checkmk.com/latest/en/self_monitoring.html), [Terraform IAM policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy).
