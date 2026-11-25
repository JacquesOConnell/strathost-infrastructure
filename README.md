# StratHost infrastructure

I implement the supplied three-AZ WordPress hosting architecture with small service modules and separate server scripts. The source diagram, master plan and detailed engineering specification are preserved. No StratHost resources have been deployed.

## Start here

- [Implementation record: what I used and why](docs/IMPLEMENTATION-RECORD.md)
- [Deployment order, inputs and acceptance](docs/DEPLOYMENT.md)
- [Separate AWS recommendations](docs/RECOMMENDATIONS.md)
- [Detailed pre-development specification](TERRAFORM-IMPLEMENTATION-PLAN.md)
- [Master plan](STRATHOST-MASTER-PLAN.md)
- [Current validation evidence](docs/validation/2026-11-25.md)

The main repository root connects modules directly. I use explicit named resources, simple inputs and short purpose/plan-reference comments. There is no platform wrapper, Auto Scaling Group, ECS or Kubernetes. Terraform defines three fixed Docker hosts, one VPN and one Checkmk server. The Docker hosts share Regional EFS and an RDS Multi-AZ database. The public, secure and internal ALBs remain independent.

## Service layout and local status

| Area | Location | Local verification |
|---|---|---|
| State bucket/key and native locking | [bootstrap](bootstrap/README.md) | Valid; 3 mocked runs |
| VPC, subnets, NAT, routing, NACL/defaults and S3 endpoint | [networking](modules/networking/README.md) | Valid; 5 mocked runs |
| Dedicated workload security groups | [security](modules/security/README.md) | Valid; 4 mocked runs |
| Seven workload KMS keys | [encryption](modules/encryption/README.md) | Valid; 2 mocked runs |
| Machine roles and profiles | [IAM](modules/iam/README.md) | Valid; 1 mocked run |
| S3 and shared EFS | [storage](modules/storage/README.md) | Valid; 4 mocked runs |
| Private RDS primary/standby | [database](modules/database/README.md) | Valid; 3 mocked runs |
| Five EC2 servers and Checkmk data volume | [EC2](modules/ec2/README.md) | Valid; 1 mocked run |
| Three ALBs, target groups and listeners | [load balancing](modules/load-balancing/README.md) | Valid; 2 mocked runs |
| Private administration/application names | [DNS](modules/dns/README.md) | Valid; 1 mocked run |
| Daily EC2/EFS recovery points | [backup](modules/backup/README.md) | Valid; 1 mocked run |
| Checkmk permissions/inventory and diagnostic flow logs | [monitoring](modules/monitoring/README.md) | Valid; 1 mocked run |
| Separate edge root: Access and optional DNS publication | [Cloudflare](cloudflare/README.md) | Valid; module has 2 mocked runs |
| Root module connections | Root service `.tf` files | Valid; 1 mocked run |
| Docker, WordPress, Checkmk and WireGuard setup | [scripts](scripts/README.md) | Syntax/Compose and 5 backup-check tests pass; 32 local application checks pass |

Checkmk is the monitoring platform. Native AWS metric API reads and diagnostic RDS/VPC logs support it; no parallel CloudWatch alarm/dashboard/agent or SNS alert stack is created. Source configuration is not proof of operational monitoring, backup completion or successful restores.

## Decisions and traceability

[Service layout](docs/decisions/0001-service-layout.md), [straightforward modules](docs/decisions/0002-straightforward-modules.md) and [supplied architecture scope](docs/decisions/0003-supplied-design-and-recommendations.md) record the selected approach. The diagram's single NAT remains the default. Per-AZ NAT, automatic instance replacement, private Checkmk placement and other improvements stay in the recommendations.

Code comments link to relevant plan sections and explain important settings. `ARCH` identifies diagram requirements, `MASTER` identifies master-plan selections and `DESIGN` identifies engineering decisions. Identifiers such as A08/D01 refer to the plan's traceability table. Service READMEs provide fuller reasoning without narrating each Terraform line.

## Run local checks

The pinned toolchain is Terraform **1.17.2**, AWS provider **6.73.0** and optional Cloudflare provider **5.18.0**. Generated root lockfiles are retained. Child-module lockfiles are local validation artifacts and ignored. On a machine with the pinned Terraform and approved registry access:

```powershell
pwsh -File scripts/validate.ps1 -Initialize
python -m unittest discover -s scripts/checkmk/tests -v
```

After initialization, omit `-Initialize`. An explicit executable can be selected with `-TerraformPath`. Set any isolated CLI configuration outside this source when workstation policy requires it. The script checks schemas and mocked plans; it never runs a live AWS plan/apply. All **31 mocked Terraform runs** and **5 Python unit tests** pass. Compose parsing and Bash/Python syntax checks also pass. A subsequent Docker Linux run built the WordPress image, linted PHP and passed **32 application integration checks**, including verified/rejected database TLS, Access token/authentication boundaries, shared sessions/uploads and readiness failure/recovery. See the [application report](docs/validation/application-2026-11-25.md). These used disposable MySQL/storage/issuer fixtures; Ubuntu/systemd installers, actual AWS/Cloudflare access, VPN and Checkmk remain live acceptance work.

## Deployment boundary

Use the examples under `environments/` and `cloudflare/` only after replacing every placeholder with approved account, AMI, role, domain/certificate and release values. No lab account, access key or private credential is a default. Credentials, state, tfvars, backend settings, plans, local tools and generated delivery files stay out of Git.

The root creates empty site/VPN secret containers; RDS manages its administrator secret. Secret values and VPN keys never enter Terraform. Provisioning does not initialize WordPress databases, install applications, register agents, publish forwarding rules or prove readiness. Follow the separate scripts and deployment runbook; application forwarding and Cloudflare publication default off until protections are tested.
