# EC2 servers

I used five explicit resources: three fixed Docker hosts in application A/B/C, WireGuard in public A and Checkmk in public C. No Auto Scaling Group is added. Each Docker host runs the same three sites, mounts the same Regional EFS through site access points, and joins each site's ALB target group.

| Host | Private address | Production / test | Root disk |
|---|---|---|---|
| Docker01/02/03 | `10.0.4.10`, `10.0.5.10`, `10.0.6.10` | t3.large / t3.small | 50 / 20 GiB |
| VPN | `10.0.1.10` | t3.small / t3.micro | 20 / 15 GiB |
| Checkmk | `10.0.3.30` | t3.medium / t3.medium | 50 / 30 GiB |

VPN receives an EIP and disables source/destination checking for controlled forwarding. Checkmk receives an intentional public IPv4 address for outbound Internet access from the diagram's public subnet. Its security group restricts administration to VPN/SSM. Private placement is a separate recommendation. Checkmk also receives an encrypted 50/20 GiB data volume; configuration waits for attachment and identifies it by volume ID.

All hosts require pinned Canonical Ubuntu 24.04 AMD64 AMI IDs, verified through owner/family/architecture filters. IMDSv2 is mandatory with hop limit one. Root gp3 disks are encrypted; no SSH keypairs or inbound SSH are used. Standard CPU credits bound burst-surplus costs but may throttle exhausted hosts. Detailed CloudWatch monitoring is off; Checkmk uses agents and available AWS metrics. Sizes need load testing.

Only non-secret bootstrap instructions belong in user data. Root composition must wait for routes, IAM policies and security rules. Fixed addresses require draining and replacing hosts one at a time. No automatic replacement or zero-downtime claim is made.

Schema validation and one mocked topology/security test pass. Real AMI resolution, SSM, EBS mounting, capacity, replacement and application checks remain pending.

References: [IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-options.html), [Nitro EBS IDs](https://docs.aws.amazon.com/ebs/latest/userguide/identify-nvme-ebs-device.html), [CPU credits](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances.html), [Terraform EC2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance), [volume attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment).
