#!/usr/bin/env bash
# Plan 19: install a matching agent and register pull-mode TLS without command-line passwords.
set -euo pipefail
umask 077
[[ $EUID == 0 && -t 0 ]] || { echo 'Run with sudo in an interactive SSM terminal.' >&2; exit 1; }
[[ $# == 4 ]] || { echo 'Usage: sudo bash install-agent.sh PACKAGE.deb SHA256 HOSTNAME CHECKMK-PRIVATE-IP' >&2; exit 1; }
package=$(realpath "$1")
checksum=$2
host_name=$3
server=$4
[[ $checksum =~ ^[0-9a-fA-F]{64}$ && $host_name =~ ^[a-z0-9][a-z0-9.-]+$ && $server =~ ^(10\.0\.3\.30|127\.0\.0\.1)$ ]] || exit 1
printf '%s  %s\n' "$checksum" "$package" | sha256sum --check --status
[[ $(dpkg-deb -f "$package" Package) == check-mk-agent ]] || exit 1
[[ ! -e /var/lib/cmk-agent/registered_connections.json ]] || {
  echo 'Existing registration found. Inspect cmk-agent-ctl status; do not overwrite trust automatically.' >&2; exit 1;
}
# Mask the listener through package installation to avoid temporarily serving unencrypted data.
systemctl mask --now check-mk-agent.socket
apt-get install -y "$package"
# Direct receiver port avoids the earlier mistake of treating Apache port 80 as the registration receiver.
# Compare the presented site certificate with the server's certificate before accepting it.
cmk-agent-ctl register --hostname "$host_name" --server "$server:8000" --site strathost --user agent_registration
systemctl unmask check-mk-agent.socket
systemctl enable --now check-mk-agent.socket cmk-agent-ctl-daemon.service
cmk-agent-ctl status
echo 'Now test this host from Checkmk, discover services, accept them and activate the reviewed changes.'
