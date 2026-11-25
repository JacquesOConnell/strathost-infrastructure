# Networking

This module defines the network in sections 6 and 7 of the [implementation plan](../../TERRAFORM-IMPLEMENTATION-PLAN.md). It creates a dedicated VPC; it does not adopt the account's default VPC or change a shared network. Schema validation and five mocked test runs pass with AWS provider 6.73.0. Nothing has been deployed.

## What I used and why

| Resource or setting | Selection and reason | Provenance |
|---|---|---|
| VPC | `10.0.0.0/16`, IPv4 only, default tenancy, DNS support and hostnames enabled | Diagram CIDR; plan configuration |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24` | Diagram |
| Application subnets | `10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24` | Diagram |
| Database subnets | `10.0.7.0/24`, `10.0.8.0/24`, `10.0.9.0/24` | Diagram |
| Availability zones | Stable `a`, `b`, `c` keys with AZ names checked against available standard zones; physical IDs are output for review | Simplified input interface; account/zone mapping remains a pre-deployment check |
| Public address allocation | Automatic allocation disabled on all subnets; public resources receive intentional addressing later | Security design |
| Internet gateway | One attached to the VPC, shared by public subnets | AWS resource model; corrects the diagram's AZ placement |
| Diagram NAT | One zonal NAT in public C, shared by all application route tables | Supplied diagram; acknowledged AZ dependency |
| Optional per-AZ NAT | Three zonal NATs; each application route table uses the matching AZ | Separate resilience recommendation, selected only by setting single_nat_gateway=false |
| Routes | One public table, three application tables and one database table; all nine associations explicit | Plan; removes reliance on main-table inheritance |
| Database egress | No internet, NAT, VPN or S3 endpoint routes | Isolation design; security groups will restrict database access separately |
| Default security group | No ingress or egress; unused by workloads | Quarantines accidental default-group use |
| Default route table | No non-local routes or virtual gateway propagation | Quarantines accidentally unassociated subnets |
| Default NACL | Explicit IPv4 allow-all ingress/egress at rule 100; all nine subnets managed together | Master plan chooses security groups as the enforcement boundary |
| S3 endpoint | Gateway endpoint on the public and application route tables only | Private regional S3 path; no endpoint ENIs or security group required |

The address space is deliberately fixed to the supplied diagram. I kept the resource definitions separate by purpose rather than creating a general-purpose network generator. The module uses ordinary `for_each` maps only where the architecture repeats a resource across three slots.

## Inputs and outputs

Inputs are `environment`, `availability_zones`, `single_nat_gateway`, `cost_center`, `s3_endpoint_policy_json` and optional `additional_tags`. The provider is supplied by the environment root and must target the approved account in `eu-west-1`. AZ names are account inputs; the physical name-to-ID mapping is returned for pre-deployment review. Confirm that mapping in the intended account rather than copying test fixtures.

Outputs expose the VPC ID/CIDR, subnet maps, AZ names/IDs, application route tables, NAT IDs and S3 endpoint/prefix-list IDs. They are identifiers, not readiness signals. The composition root must order server configuration after network routes, default controls and endpoint policies are installed.

The module call uses ordinary values. This example illustrates the interface; its AZ names and endpoint policy still require account-specific review:

```hcl
module "networking" {
  source = "./modules/networking"

  environment = "test"
  cost_center = "InterviewSandbox"
  availability_zones = {
    a = "eu-west-1a"
    b = "eu-west-1b"
    c = "eu-west-1c"
  }
  single_nat_gateway      = true
  s3_endpoint_policy_json = data.aws_iam_policy_document.s3_endpoint.json
}
```

The diagram baseline uses `single_nat_gateway = true` in all environments. Set it false only when selecting the separately documented per-AZ recommendation. The example assumes the composition root defines the reviewed endpoint policy; it is not a complete standalone deployment.

## Endpoint policy boundary

The environment root supplies the endpoint policy. Networking owns routes and the endpoint; it does not invent runtime role or storage permissions. This small interface replaces embedding workload IAM decisions in the networking module. The composition root will build the policy from approved S3 export paths, exact runtime roles and required regional AWS-managed artifact buckets. It must not include the Terraform state, ALB log or audit buckets.

The input validation checks JSON structure only. It is not an IAM policy analyser. The mock test's read-only agent-download policy is a test fixture and is not the full deployment policy. Before deployment, include the exact artifact buckets required by the selected SSM operations and grant the matching instance-profile permissions. An endpoint policy only limits access; it does not grant permissions missing from IAM or bucket policies. Restricting it without preserving required SSM reads can break agent updates or patching.

## Validation and outstanding checks

The tests cover tier count and distinct CIDRs, public-address defaults, NAT routing, database route exclusion, default-object quarantine, required tags, diagram single-NAT availability and optional per-AZ routing, unavailable-AZ rejection and missing endpoint-policy rejection. They use mocked data and plan commands; even a passing run would not prove AWS connectivity or IAM authorisation.

Run from the repository root after provider installation is available:

```powershell
terraform -chdir=modules/networking init -backend=false
terraform -chdir=modules/networking validate
terraform -chdir=modules/networking test
```

Deployment acceptance still requires a reviewed plan, confirmed AZ mapping and quotas, real routing/SSM tests, default-object adoption review, and actual delivery of the VPC Flow Logs defined by monitoring. The NACL is deliberately permissive; database isolation depends on routing and the later dedicated security groups. This module alone is not the finished security boundary.

References: [AWS AZ IDs](https://docs.aws.amazon.com/ram/latest/userguide/working-with-az-ids.html), [NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html), [S3 gateway endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html), [SSM artifact buckets](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-technical-details.html), [default NACL](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl), [default route table](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_route_table), [Terraform provider mocking](https://developer.hashicorp.com/terraform/language/tests/mocking).
