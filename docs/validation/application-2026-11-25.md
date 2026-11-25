# Local application verification — 25 November 2026

## Outcome

I built the actual WordPress Dockerfile and ran 32 successful integration checks in disposable Linux containers. The tests used the production Compose configuration, PHP drop-ins and the Nginx template extracted directly from `scripts/wordpress/deploy.sh`. All three PHP files passed lint during the image build.

Docker Engine 29.7.2 ran WordPress 7.1.5 with PHP 8.3.37 on Debian GNU/Linux 13 containers. The database fixture used MySQL 8.4.13 and the proxy/HTTPS issuer fixture used Nginx 1.30.8 Alpine. Exact immutable digests, the built image ID, source SHA-256 values and individual results are in [the sanitized evidence](application-results-2026-11-25.json).

This is local application evidence. It is not an Ubuntu EC2 deployment, a live RDS/EFS test or approval to activate public routing.

## What passed

| Area | Observed result |
|---|---|
| Build and syntax | Actual Dockerfile builds from a pinned base; all three PHP files pass lint |
| Startup/readiness | Four test replicas initialize WordPress and return successful real database/uploads readiness |
| Routing | Public/internal pages render; wrong Host and named-host diagnostic paths, including a path-info variant, are rejected |
| Access rejection | Missing, malformed, expired, unsigned, forged, wrong issuer/audience, future, not-yet-valid and unknown-key tokens are rejected |
| Access success | Correctly signed token succeeds after HTTPS public-key retrieval using a trusted fixture CA |
| Key lifecycle | Rotated key succeeds after cache refresh; expired cache plus issuer outage fails closed and recovers |
| Authorization boundary | A valid Access token still redirects an unauthenticated WordPress administrator request to WordPress login; an identity header alone is rejected |
| Database TLS | Real encrypted connection succeeds; wrong certificate hostname and untrusted CA fail closed |
| Database grants | The application fails closed when the selected database is outside its fixture user's grants |
| Replica state | Two public replicas read one shared uploaded file; an administrator session remains valid when switching replicas |
| Failure detection | Unwritable uploads and a stopped database fail readiness; readiness recovers when each is restored |
| Startup guard | Linux helper exits through its missing-mount guard before secret retrieval; shell errors are not counted as success |

The test uses two public replicas plus one secure and one internal application container. This is a disposable test layout for shared-state checks; it does not add a fourth EC2 host to Terraform.

## Fixture issues and corrections

The first database initialization check saw MySQL's temporary setup server before the real TCP server was ready. I corrected the fixture readiness probe to wait for TCP. A fixture directory name also collided with an existing secure-site secret directory; allowing that directory to exist resolved it. Neither correction required relaxing database TLS or changing WordPress application behaviour.

The initial internal-only site bridge prevented Docker Desktop from exposing its loopback ports. I kept the database/issuer network internal, gave each site its separate normal bridge and bound published test ports only to `127.0.0.1`. The AWS networking configuration was unchanged.

The completed run passed every check. The final authorization cases and tightened guard assertion were also verified. No cloud deployment was used for these tests.

## Isolation, artifacts and cleanup

The harness generates random fixture passwords, salts, certificates and signing keys under ignored `.tools/strathost-qa-{run}/`. Fake RDS and Access hostnames resolve to containers on its private database network. It uses no AWS credentials or actual Cloudflare account/IdP. The installer suppresses mail, and no real notification is sent.

The harness removes its own Compose projects, containers, networks and volumes. Cleanup was independently verified. Images and ignored diagnostics remain locally available for inspection. No unrelated Docker resources were pruned or stopped. The committed JSON contains only test names/results, runtime/image identifiers, source hashes and cleanup confirmation; it contains no fixture passwords or private keys.

Reproduction instructions and test dependencies are in [tests/application](../../tests/application/README.md). Upgrading image versions or changing the PHP, Compose or proxy configuration requires rerunning the relevant tests.

## What remains unproven

Shared Docker volumes substitute for uploads; they do not test EFS access-point ownership, TLS/IAM, NFS availability or cross-AZ behaviour. Local MySQL certificates test the actual client's verification logic but do not establish RDS provisioning, failover, Secrets Manager access or recovery. The local HTTPS signing-key fixture tests JWT validation and failure handling; actual Cloudflare Access policy, MFA, users, edge/origin requests and direct-origin bypasses still need account-backed tests.

Ubuntu package installation, systemd/reboot ordering, VPN forwarding/DNS/peer revocation, Checkmk installation/agents/notifications, AWS IAM/log/backup delivery, production capacity and full restores remain live acceptance work. The three fixed-host fleet and single VPN/Checkmk availability limitations are unchanged.

The next step is the Terraform code walkthrough and approval of deployment-specific inputs. Any live plan/apply remains a separately reviewed action under the [deployment runbook](../DEPLOYMENT.md).

References: [official WordPress image](https://hub.docker.com/_/wordpress), [official MySQL image](https://hub.docker.com/_/mysql), [Cloudflare token-validation requirements](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/).
