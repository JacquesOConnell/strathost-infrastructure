# Docker host configuration

I use Ubuntu 24.04 AMD64, Docker's official signed apt repository, explicitly selected Engine/CLI, containerd, Compose and Buildx package versions, and an approved SHA-256-verified EFS-utils DEB. Build EFS-utils from an approved pinned AWS release in a controlled build environment; do not assume Ubuntu includes an `amazon-efs-utils` apt package.

```bash
apt-cache madison docker-ce containerd.io docker-compose-plugin docker-buildx-plugin
sudo bash scripts/docker/install.sh ENGINE_VERSION CONTAINERD_VERSION COMPOSE_VERSION BUILDX_VERSION /approved/amazon-efs-utils.deb EFS_SHA256
sudo docker version
sudo docker compose version
```

These uppercase values are release-manifest inputs, not commands to paste unchanged. Record exact selected package versions, EFS source commit/build provenance and hash. The script validates the OS/architecture, installs prerequisites, bounds local logs to five 20 MB files, enables live restore and validates daemon configuration. It refuses to overwrite a different existing daemon configuration and does not grant users the root-equivalent Docker group or expose a remote API.

Run installation on fresh or deliberately drained hosts: it restarts Docker to apply its settings. Package/service behaviour must be tested on the selected AMI before production use. Repeated runs preserve a matching configuration; they are not a rolling upgrade controller.

Install the pinned, signed AWS CLI using `scripts/bootstrap/install-aws-cli.sh` before runtime secret/export operations. Its inputs are an approved CLI zip, SHA-256, detached signature, official public key/fingerprint and exact version. Verify these through AWS's published installation instructions. Temporary role credentials come from IMDSv2; never run `aws configure` with long-lived keys on the hosts.

WordPress images, mounts, credentials and controlled deployment belong to [WordPress](../wordpress/README.md). Bash syntax passes locally; no packages, Docker daemon or EFS mounts have been exercised on Ubuntu yet.

References: [Docker Ubuntu installation](https://docs.docker.com/engine/install/ubuntu/), [EFS-utils installation](https://docs.aws.amazon.com/efs/latest/ug/installing-amazon-efs-utils.html), [AWS CLI signature verification](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
