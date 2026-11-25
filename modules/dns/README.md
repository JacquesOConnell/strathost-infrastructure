# Private DNS

I used a VPC-associated Route 53 private zone, an alias for internal WordPress pointing to the internal ALB, and an A record for Checkmk's fixed private address. Both names must belong to the approved private suffix. This supplies the DNS needed for private HTTPS and follows plan section 15; it is supporting configuration rather than an additional application workload.

VPN clients query the WireGuard-only DNS forwarder, which forwards to the VPC resolver. No public record containing these private addresses or paid Resolver inbound endpoint is created. Existing ACM certificates and Checkmk's separately installed certificate must match their respective names. Public WordPress DNS remains in Cloudflare.

Schema validation and one mocked test pass. Real VPN name resolution, zone-shadowing effects on existing names, certificate trust and private HTTP access require live tests.

References: [private zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html), [ALB aliases](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-elb-load-balancer.html), [Terraform zone](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone).
