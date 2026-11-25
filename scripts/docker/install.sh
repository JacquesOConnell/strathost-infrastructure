#!/usr/bin/env bash
# Plan 14: explicit Docker releases, no convenience script piped into a privileged shell.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 6 ]] || {
  echo 'Usage: sudo bash install.sh ENGINE_VERSION CONTAINERD_VERSION COMPOSE_VERSION BUILDX_VERSION EFS_UTILS.deb EFS_SHA256' >&2; exit 1;
}
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 && $(dpkg --print-architecture) == amd64 ]] || exit 1
engine_version=$1
containerd_version=$2
compose_version=$3
buildx_version=$4
efs_package=$(realpath "$5")
[[ $6 =~ ^[0-9a-fA-F]{64}$ ]] || exit 1
printf '%s  %s\n' "$6" "$efs_package" | sha256sum --check --status
[[ $(dpkg-deb -f "$efs_package" Package) == amazon-efs-utils ]] || exit 1
apt-get update
apt-get install -y ca-certificates curl gnupg jq nfs-common "$efs_package"
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error --proto '=https' --tlsv1.2 https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y "docker-ce=$engine_version" "docker-ce-cli=$engine_version" "containerd.io=$containerd_version" \
  "docker-compose-plugin=$compose_version" "docker-buildx-plugin=$buildx_version"
install -d -m 0755 /etc/docker
desired_config=$(mktemp)
trap 'rm -f -- "$desired_config"' EXIT
cat > "$desired_config" <<'EOF'
{
  "log-driver": "local",
  "log-opts": {"max-size": "20m", "max-file": "5"},
  "live-restore": true,
  "userland-proxy": false
}
EOF
if [[ -f /etc/docker/daemon.json ]] && ! cmp -s /etc/docker/daemon.json "$desired_config"; then
  echo 'Existing Docker configuration differs. Review and merge before restarting Docker.' >&2; exit 1
fi
install -m 0644 "$desired_config" /etc/docker/daemon.json
dockerd --validate --config-file=/etc/docker/daemon.json
systemctl enable --now docker
systemctl restart docker
docker version
docker compose version
# Do not add operator accounts to the root-equivalent docker group automatically.
