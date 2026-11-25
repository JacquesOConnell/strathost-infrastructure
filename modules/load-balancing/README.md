# Three independent application load balancers

I used separate public, secure and internal ALBs. Public/secure span the public subnets; internal spans the application subnets. Each has a dedicated security group, target group and HTTPS listener. The three fixed Docker hosts are registered in each target group: nine attachments in total. Proxy ports 8080/8081/8082 keep site classes distinct; an ALB never targets another ALB.

Issued regional ACM certificate ARNs are required inputs. I do not import certificate private keys or create DNS-validation records in an externally owned zone. Listeners use TLS 1.2/1.3 policy, fixed default 403 responses, hostname-specific routing and independent disabled-by-default activation flags. Secure activation additionally requires an attestation of recorded origin JWT/bypass tests. That flag records the deployment decision; the application validator supplies authentication.

Private backend HTTP is an explicit plan decision, restricted by security groups; this is not end-to-end TLS. Checks use `/healthz` with exactly HTTP 200, 30-second intervals, 5-second timeouts and 2/3 healthy/unhealthy thresholds. Drain delay is sixty seconds and slow start thirty seconds. Stickiness is disabled because replicas share a database, uploads and site salts. Readiness must actually check the application, database and uploads.

ALB access logs use separate class prefixes in the compatible SSE-S3 bucket. HTTP/2, strict desync handling, invalid-header dropping and production deletion protection follow the plan. Test legitimate requests before acceptance. No HTTP listener or implicit TLS downgrade is created. Custom origin mTLS remains an optional separate proposal.

Schema validation and two mocked tests pass. Certificate status/name coverage, Cloudflare origin restriction, unauthenticated and wrong-host rejection, private DNS/VPN access, all nine targets, log delivery and single-AZ loss remain runtime tests. Keep forwarding disabled while configuring hosts.

References: [ALBs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html), [target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html), [health checks](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html), [Terraform ALB](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb), [listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener).
