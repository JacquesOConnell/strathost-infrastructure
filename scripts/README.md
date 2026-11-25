# Server configuration scripts

Terraform defines infrastructure. Separate scripts configure the server roles after provisioning:

| Folder | Responsibility |
|---|---|
| `docker` | Install pinned Docker Engine and Compose packages and configure the Ubuntu hosts |
| `wordpress` | Render and deploy per-site Compose and proxy configuration, shared EFS paths and health checks |
| `checkmk` | Install the StratHost Community package, create the site and configure server monitoring |
| `vpn` | Install WireGuard and configure approved peer and private-destination access |
| `bootstrap` | Start the AMI's SSM agent; verify and install an explicitly selected AWS CLI artifact |

Executable installation/configuration scripts are now present, with role-specific runbooks. Software package versions, image digests and artifact hashes are explicit deployment inputs. Runtime Secrets Manager reads use the EC2 instance profile. Credentials and WireGuard private keys are not Terraform variables, state values, user data or repository files. The one-time database administrator credential is supplied through a separate controlled initialization workflow and removed afterwards.

The independent Checkmk Ultimate trial is not the StratHost server configuration. Configuration scripts will follow the StratHost technical plan and remain separate by purpose. An installation will be reported as operational only after the relevant service and access tests have run.

Local checks cover Bash/Python syntax, Compose configuration and backup-freshness logic. The WordPress image now builds and passes PHP lint plus 32 Linux-container application checks. These cover TLS, Access authentication, WordPress authorization, sessions, shared test storage and readiness. Ubuntu/systemd installation, EFS/AWS permissions, VPN peers and actual Checkmk/Cloudflare integration remain untested. Follow [deployment and acceptance](../docs/DEPLOYMENT.md) before applying or running the scripts.
