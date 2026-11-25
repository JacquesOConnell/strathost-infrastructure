# Disposable application integration tests

I test the production WordPress Dockerfile, Compose configuration, PHP files and generated Nginx proxy template against local Linux containers. No AWS credentials, AWS API calls, real Cloudflare account or real user identities are used. This is an application compatibility/security test, not an EC2 deployment test.

The fixture contains two public WordPress replicas, one secure site and one internal site, plus MySQL and an HTTPS signing-key endpoint. Four application containers make it possible to test replica sessions while keeping the site classes separate. They do not change the three-EC2 architecture. Docker volumes substitute for shared uploads; they do not emulate EFS IAM, NFS or cross-AZ networking.

## Inputs and execution

Requirements are a running Linux Docker engine, Python and the test-only dependency in `requirements.txt`. The exact official image digests are in `images.json`; they were resolved from WordPress 7.1.5/PHP 8.3 Apache, MySQL 8.4.13 and Nginx 1.30.8 Alpine. They are tested local artifacts, not automatic production release selections.

```powershell
python -m pip install -r tests/application/requirements.txt
docker pull wordpress@sha256:9b46af6a41fd0dcb2e5cf85033a6350d05010356847ede1cfcac5cf94292eb26
docker pull mysql@sha256:8c233bad33d520a7aae1c1e619c3a9775f4a1ba2d463d692fada04ec7f40be00
docker pull nginx@sha256:6437a63b5c529f0e06162b3f593c0154cff6fa2ea0f94fd7c27928cb399e022d
python tests/application/run.py
```

The harness uses an isolated Docker CLI configuration, so it does not need personal registry credentials. It builds a local image from the pinned base and lints all three PHP files during the build. Random fixture credentials, temporary certificate keys, logs and results stay under ignored `.tools/strathost-qa-{run}/`. Mail is explicitly suppressed in the test installer. Private test ports bind only to `127.0.0.1`; the database/signing-key network is internal. The site bridges allow Docker Desktop loopback publishing and are separate per project. Fake RDS/Access hostnames resolve to fixture containers on the test network.

Cleanup removes only the generated project containers/networks and their volumes. Downloaded images, the built test image and ignored diagnostics remain available for review. No global prune, Docker Desktop shutdown or removal of unrelated resources is performed. Check remaining owned resources if execution is forcibly interrupted.

## Behaviour checked

- Image build and PHP lint; four real WordPress installations and readiness.
- Public/internal pages, wrong Host rejection and blocked named-host diagnostic routes.
- Missing, malformed, expired, unsigned, forged, wrong-issuer/audience, future and unknown-key token rejection.
- Valid token acceptance using HTTPS key retrieval, key rotation, issuer outage rejection and recovery.
- Verified database TLS, hostname mismatch and untrusted-CA rejection, permission denial and recovery.
- Shared uploaded files and an administrator login session surviving a replica change.
- Readiness failure/recovery for unwritable uploads and a database outage.
- The Linux startup helper's missing-mount guard, checked independently of shell/runtime failures.

Thirty-two checks passed on 25 November 2026. The [sanitized evidence](../../docs/validation/application-results-2026-11-25.json) records image identifiers, runtime versions, source hashes and cleanup. The [test report](../../docs/validation/application-2026-11-25.md) explains the fixture fixes and remaining deployment tests.

The actual RDS service, EFS access points/TLS/IAM, AWS permissions, Ubuntu/systemd installers, VPN, Checkmk, Cloudflare IdP/policies, mail delivery, load capacity, failover and restores remain separate acceptance work. A private registry or a different production image/version needs its own review and test run.
