# WordPress site configuration

I deploy three separate Compose projects on each of the three Docker hosts. Each site uses the same image, database, uploads access point and shared site salts on all hosts. Nginx exposes only that site's dedicated private proxy port: public 8080, secure 8081, internal 8082. WordPress has no published host port. No database container is deployed; RDS is the shared database.

## 1. Build and review images

Build the WordPress Dockerfile using an approved official Apache base image **by digest**. It adds a TLS-verifying RDS database drop-in, readiness endpoint and protected-origin Access validator. Add the approved site plugins/themes to the image in the build workflow; do not install them interactively on one replica. Test PHP/OpenSSL/mysqli compatibility, scan the image and publish to the approved registry. Record the resulting immutable digest. Use a reviewed Nginx digest as well.

```bash
docker build --build-arg WORDPRESS_BASE_IMAGE=wordpress@sha256:APPROVED_BASE_DIGEST -t APPROVED_REGISTRY/strathost-wordpress:RELEASE scripts/wordpress
```

This remains a production build example requiring an approved release digest. Local testing subsequently built this Dockerfile against a pinned WordPress 7.1.5/PHP 8.3.37 base; the test-only image/digests and results are recorded under tests/application and docs/validation. That does not automatically approve a production release. A private registry additionally needs a scoped pull-authentication workflow; that integration is not assumed by the runtime IAM policy. Using reviewed public artifacts avoids requiring ECR in the supplied design.

## 2. Mount shared uploads

Run once per site on each host using the filesystem and access-point outputs:

```bash
sudo bash scripts/wordpress/mount-uploads.sh public_wordpress fs-APPROVED_ID fsap-APPROVED_ID
```

Repeat for secure/internal sites. The helper uses EFS TLS, IAM authentication and the correct access point. It refuses to hide existing local uploads. All three hosts mount the same site data; do not create three different filesystems. Verify cross-AZ file read/write access, POSIX ownership and mount recovery before continuing.

## 3. Prepare credentials, certificates and configuration

Populate each Terraform-created site secret outside Terraform. Its JSON fields are `database_user`, `database_password`, `auth_key`, `secure_auth_key`, `logged_in_key`, `nonce_key`, `auth_salt`, `secure_auth_salt`, `logged_in_salt` and `nonce_salt`. Generate strong independent credentials and salts per site. The same site's secret is shared across replicas so login sessions remain consistent; different sites must not share users or salts. There are no real example passwords in the repository.

Obtain the current official RDS CA bundle, verify its source/checksum, and place it at the approved root-owned path. The database drop-in explicitly configures CA verification and encrypted connections, including reconnects. Wrong hostname, untrusted CA or absent TLS must fail the acceptance test.

Copy `site.example.json` to a protected operator configuration. Replace every placeholder; set the host's own private IP, correct site key/hostname/database/secret, reviewed image digests, CA path and measured memory limit. Test's 256 MB example is a starting limit, not proven WordPress capacity. For secure WordPress supply the exact Cloudflare Access issuer and audience output. Keep per-site JSON under `/etc/strathost/wordpress/{site}.json`, owned by root.

## 4. Initialize the three site databases

Install an approved MySQL 8 client on the controlled application host. An authorized operator retrieves the RDS administrator secret into a root-owned mode-0600 JSON file under `/run` through a separately authorized initialization session. The regular Docker instance profile deliberately cannot retrieve this administrator secret.

```bash
sudo python3 scripts/wordpress/create-databases.py /run/approved-admin.json /etc/strathost/wordpress /etc/strathost/rds-ca-bundle.pem
```

The script checks RDS endpoint allocation, uses a private MySQL option file, and creates the three databases named after their site keys. Each distinct site user gets privileges only on its own database and only from the three fixed Docker private addresses, with SSL required. Credentials are not command-line values or logged SQL. Remove the temporary administrator file and end its privileged session after successful validation. Re-running changes site passwords to the selected secret values: coordinate rotation across replicas before using it again.

## 5. Deploy a drained host

Drain the host from all three target groups and wait for existing connections before restarting its services. On each Docker host, repeat for the three site configurations:

```bash
sudo bash scripts/wordpress/deploy.sh /approved/public_wordpress.json
sudo systemctl status strathost-wordpress-public_wordpress
```

The script installs a mount-dependent systemd unit, restrictive configuration, hostname-separated proxy and Compose project. At boot/start the helper reads only the site's secret, places files in root-only `/run/strathost/{site}` and exposes the needed files read-only to its container. The files are readable by the application user inside the container; the host parent directory stays root-only. Secret values are not Docker environment values. The root filesystem and Docker daemon remain trusted privileged boundaries.

Anonymous WordPress core/plugin storage is recreated on deployment so an old container volume does not preserve stale image files; uploads stay on EFS. WordPress file modification is disabled. The service waits for mounts and refuses local fallback. Container automatic restart is deliberately off; systemd controls boot ordering and Checkmk detects failures. A stopped workload requires controlled restart/recovery. This is not a self-healing fleet.

`/healthz` accepts direct target-health requests on the proxy's default host and checks WordPress, database and uploads writability. Named external host requests cannot use this diagnostic route or the underlying PHP endpoint. Confirm successful initialization and actual target health before returning the host to service; do not treat a running container as readiness.

## 6. Secure and internal access

Secure origins independently validate the Access JWT's RS256 signature, configured issuer, exact audience and expiry/issued/not-before claims. Keys are fetched only from the configured trusted issuer, cached for five minutes, and unknown keys fail closed until refresh. No identity header grants a WordPress account or administrator role. CLI maintenance and the direct readiness script are explicit local bypasses, not public routes.

Test the pinned implementation with missing, malformed, forged, expired and wrong-audience tokens; account for key rotation and issuer unavailability. Keep secure routing disabled until these tests pass. Internal WordPress requires VPN/private DNS and normal application authentication; VPN membership does not grant WordPress administrator rights.

## 7. Single-host scheduling and exports

Only Docker01 schedules due WordPress cron events and daily logical exports. Browser-triggered WP cron is disabled on replicas.

```bash
sudo bash scripts/wordpress/install-cron.sh
sudo bash scripts/wordpress/install-exports.sh APPROVED_EXPORT_BUCKET_NAME
sudo systemctl list-timers 'strathost-wordpress-*'
```

The five-minute cron job executes locally as the container's application user. Daily exports at 00:10 UTC use a TLS-verified transactional MySQL dump and an uploads archive, upload checksummed files and write a manifest last. Temp files are private and cleaned after success/failure. Ensure enough local scratch space and runtime AWS CLI/MySQL clients before enabling the timer. Docker01 is a scheduling dependency; migrating this role requires disabling the old scheduler first.

Logical exports do **not** provide an atomic database/filesystem recovery point while writes continue. The manifest states this limit. Use an approved maintenance/write-quiescence procedure when a consistent paired recovery point is required. RDS native recovery and AWS Backup's EC2/EFS recovery points are separate layers. Test export freshness, checksum verification, complete-set selection, recovery-role reads and a full application restore before accepting RPO/RTO.

## 8. Controlled updates and evidence

Release one host at a time: drain all its target groups, update approved digests/configuration, deploy, verify readiness/login/Access/DB/EFS, then re-register and observe. Keep at least two healthy hosts and test their capacity first. Database/plugin migrations may be incompatible with mixed versions; rehearse and coordinate them before deployment. Rollback requires the previous image/configuration plus a compatible database recovery plan.

Compose configuration, Bash/Python syntax and five backup-check unit tests pass. The production Dockerfile and PHP lint now pass, with 32 local Linux-container checks covering real WordPress/MySQL behaviour, verified TLS and rejection cases, Access tokens, shared sessions/uploads and readiness failure/recovery. See the [application report](../../docs/validation/application-2026-11-25.md). Tests used disposable MySQL, shared Docker storage and a local HTTPS issuer; real RDS/EFS, AWS authorization, Cloudflare account integration, Ubuntu/systemd installation and production load remain separate acceptance work.

References: [official WordPress container configuration](https://github.com/docker-library/wordpress), [wpdb](https://developer.wordpress.org/reference/classes/wpdb/), [Cloudflare JWT validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/), [Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/), [EFS TLS](https://docs.aws.amazon.com/efs/latest/ug/encryption-in-transit.html), [RDS TLS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html).
