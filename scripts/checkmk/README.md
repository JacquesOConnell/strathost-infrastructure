# StratHost Checkmk configuration

This is the StratHost Community deployment, separate from the Ultimate trial lab. These scripts are source artifacts; no installation has been run on an AWS Ubuntu host yet.

## 1. Prepare approved inputs

Use an interactive SSM terminal on the dedicated Ubuntu 24.04 AMD64 host after the separate data-volume attachment completes. Select the Community Noble package patch, SHA-256, official signing key and independently verified fingerprint. The current official documentation illustrates Community 2.5.0p21; never silently download a changing `latest` release. Transfer approved files through the authorized HTTPS/SSM artifact workflow. Install `gnupg` if missing. No SSH keypair is required.

The official public key is at `https://download.checkmk.com/checkmk/Check_MK-pubkey.gpg`. Record the reviewed release and checksum. Tokens, private keys and passwords must remain outside Git, user data and Terraform state.

## 2. Prepare the dedicated disk

```bash
lsblk -o NAME,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
# Replace vol-ID with Terraform's checkmk_data_volume_id output.
sudo bash scripts/checkmk/prepare-data-volume.sh vol-ID --initialize-blank
```

The initialization flag is only for a newly provisioned empty disk. The script resolves the Nitro EBS ID, rejects partitioned/in-use devices and existing signatures, and mounts ext4 by UUID at `/srv/checkmk`. Omit the flag for an existing ext4 restore disk. It never formats an existing filesystem.

## 3. Install Community and create the site

```bash
sudo bash scripts/checkmk/install-server.sh /approved/checkmk.deb APPROVED_SHA256 /approved/Check_MK-pubkey.gpg APPROVED_FINGERPRINT
sudo -iu strathost omd status
curl --fail --head http://localhost/strathost/
```

The script verifies the package, binds the volume's sites directory to `/omd/sites`, creates `strathost`, prompts for `cmkadmin`'s password and starts the site. Generated credentials are captured in a root-only temporary log, replaced interactively and removed. Failed creation leaves a private diagnostic log and prints its path. A systemd mount dependency prevents normal OMD service startup without the volume. Before manual OMD commands, verify the mounts yourself. Existing/restored data is never initialized over; recovery requires the matching package, preserved numeric UID/GID, mounts and a separate restore procedure.

## 4. Configure HTTPS and access

Obtain a trusted certificate/full chain and matching private key outside Terraform. Use the chosen private hostname and configure approved DNS. Place the key in a root-only location.

```bash
sudo bash scripts/checkmk/configure-https.sh monitor.example.com /approved/fullchain.pem /approved/private-key.pem
sudo apache2ctl configtest
```

The example hostname is a placeholder. The script verifies hostname, expiry and key match. Issuance, renewal and client chain verification remain operational steps. The security group permits private VPN HTTPS, not public dashboard access. For temporary local access, run on the Windows workstation with the approved AWS role:

```powershell
aws ssm start-session --region eu-west-1 --target REPLACE_WITH_CHECKMK_INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters "portNumber=80,localPortNumber=8080"
```

Leave that session open and browse `http://localhost:8080/strathost/`. HTTP travels inside the encrypted SSM tunnel. The instance needs SSM connectivity and its profile; the workstation needs AWS CLI and Session Manager plugin. Use verified private HTTPS for ongoing VPN administration.

## 5. Register all five Linux hosts

Create hosts from the Terraform monitoring inventory in **Setup → Hosts**. Use their private addresses and `127.0.0.1` for Checkmk self-monitoring. Select agent pull mode and no SNMP. Enable/create the restricted `agent_registration` account as required by the selected release. Obtain the matching agent DEB through the authenticated site workflow and verify its SHA-256.

```bash
sudo bash scripts/checkmk/install-agent.sh /approved/check-mk-agent.deb APPROVED_SHA256 EXACT_INVENTORY_HOSTNAME 10.0.3.30
# On Checkmk itself, use 127.0.0.1 as the last argument.
sudo cmk-agent-ctl status
sudo cmk-agent-ctl dump
```

The socket stays masked during installation and remains masked if registration fails. Registration prompts for the credential and site-certificate confirmation. Compare the certificate with the trusted server before accepting. Receiver port **8000** is explicit: Apache port 80 is not the Agent Receiver. Existing trust is not overwritten automatically. Configure **Enforce agent data encryption → Accept TLS encrypted connections only**. Test connections, discover and accept services, then activate reviewed changes.

## 6. Configure the AWS collector

Create the inventory's AWS collector with **No IP**, **API integrations only**, and no SNMP/Linux agent. This prevents the earlier DNS/ping false DOWN state on a logical AWS host.

Under **Setup → Agents → VM, cloud, container → Amazon Web Services (AWS)**, create a rule restricted to this exact collector. Select instance-profile credentials, displayed as **None (on EC2 instance only)** in the observed 2.5 UI. This uses temporary EC2 role credentials. Do not enter access keys or select an additional AssumeRole option without a role ARN. Select eu-west-1 and EC2, EBS, S3, RDS and ELBv2 checks for the three ALBs. Disable classic ELB, billing, service limits and unused services. Apply Project=StratHost filters and verify actual discovery.

Create returned piggyback host names manually where required by Community: No IP, piggyback data, no agent/SNMP. Review duplicate cloud-versus-agent representations. The Ultimate lab's Dynamic Host Management is not a Community prerequisite. The selected non-limit API calls were reviewed against the official v2.5.0p21 special-agent source; quota/billing/other-service calls are outside this role's intended configuration. Test actual calls against the role and review permissions again when upgrading; investigate AccessDenied before adding permissions.

## 7. Add local and application checks

On each Docker host after EFS configuration:

```bash
sudo install -d /usr/lib/check_mk_agent/local
sudo install -m 0755 scripts/checkmk/local-storage-check.sh /usr/lib/check_mk_agent/local/strathost_efs
sudo /usr/lib/check_mk_agent/local/strathost_efs
```

Mount presence does not prove NFS responsiveness or cross-AZ read/write access; test these separately. Install the site's version-matched Docker plugin after reviewing the Python Docker SDK dependency and privileged socket access. Do not expose Docker's API over TCP. Discover container state and test a deliberately stopped container.

On Checkmk, install an approved AWS CLI release. Copy `backup-freshness.example.json` to root-owned `/etc/check_mk/strathost-backups.json`, replacing all six resource ARN placeholders and the vault name. The role needs ListRecoveryPointsByBackupVault on that vault and regional ListBackupJobs.

```bash
sudo install -d /usr/lib/check_mk_agent/local/300
sudo install -m 0755 scripts/checkmk/backup-freshness.py /usr/lib/check_mk_agent/local/300/strathost_backups
sudo /usr/lib/check_mk_agent/local/300/strathost_backups
```

The 300-second cache limits API polling. Proposed 26/36-hour thresholds need approval against the actual daily backup window and RPO. Missing or stale completed recovery points and a latest failed/aborted/expired job alert; partial jobs warn, and failed collection becomes UNKNOWN. Completed jobs with a non-success message category also warn. This does not prove successful restores or replace backup-job failure investigation. Verify RDS native backups separately.

Configure HTTPS checks for each real hostname/readiness path, certificate expiry and ALB target health. Verify VPN systemd/interface state and a real peer connection. Configure contacts, notification rules and an approved delivery method, then run a controlled notification test. No external notifications have been sent by this work.

## 8. Acceptance and troubleshooting

| Symptom or test | Action / expected result |
|---|---|
| `omd status` | All configured services running |
| Agent connection refused | Check package, socket, TLS registration and SG source on 6556 |
| Registration InvalidContentType | Use receiver port 8000, not Apache port 80 |
| No cached agent data | Confirm registration and poll again; rescan once data arrives |
| Logical AWS host DNS error / DOWN | No IP, API-only; save and activate |
| Services discovered but unmonitored | Accept services and activate reviewed changes |
| Memory warning | Inspect available RAM, processes and swap; do not hide it by raising thresholds |
| Backup collection UNKNOWN | Check config, CLI, role, vault and regional connectivity |
| EFS mount absent | Fail readiness; restore the mount before starting containers |
| Entire Checkmk instance lost | Self-monitoring cannot notify; external availability monitoring is a recommendation |

Record successful polling, denied unauthorized access, TLS checks, controlled application failure/recovery, notification delivery, backup freshness and an actual restore. Observe memory/CPU under all checks before accepting 4 GiB sizing. Lab Apache tuning and swap are troubleshooting evidence, not automatic production defaults.

References: [Ubuntu installation](https://docs.checkmk.com/latest/en/install_packages_debian.html), [OMD administration](https://docs.checkmk.com/latest/en/omd_basics.html), [TLS registration](https://docs.checkmk.com/latest/en/agent_linux.html), [AWS integration](https://docs.checkmk.com/latest/en/monitoring_aws.html), [local checks](https://docs.checkmk.com/latest/en/localchecks.html), [SSM sessions](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html).
