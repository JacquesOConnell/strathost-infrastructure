# MySQL database

I used one `aws_db_instance` with `multi_az = true`: AWS manages its primary and standby. The diagram's standby is not a read replica or a second independently configured database. All three isolated database subnets belong to the subnet group; only the Docker security group reaches port 3306.

MySQL 8.4.13 is selected subject to regional availability checks. Production uses `db.t4g.medium`, 100 GiB gp3 and a 500 GiB autoscaling ceiling; test uses `db.t4g.micro`, 20 GiB and a 100 GiB ceiling. Both preserve Multi-AZ. These are planning estimates, not measured capacity. Customer-managed keys encrypt storage, snapshots and the RDS-managed administrator secret. Terraform receives only the secret ARN. Applications must use separate per-database users provisioned outside Terraform.

I require TLS, disable general query logging, and export error/slow-query diagnostics to encrypted log groups with bounded retention. Checkmk provides monitoring; no CloudWatch alarms or SNS topics are added. Enhanced Monitoring is optional and disabled without an explicit role. Native backups retain fourteen days in production or one day in test. Deletion protection defaults on, and production cannot skip its final snapshot. Select a unique final snapshot release label and retain encryption keys for recovery.

Inputs and outputs are described in their Terraform files. Schema validation and three mocked plan tests pass. Regional engine/class availability, TLS verification, site users, failover and point-in-time recovery require live acceptance.

References: [RDS Multi-AZ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html), [managed passwords](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html), [TLS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html), [Terraform DB instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance).
