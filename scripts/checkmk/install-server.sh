#!/usr/bin/env bash
# Plan 19: attended Community installation. Approved package and signing identity are explicit inputs.
# Keep this out of cloud-init: initial credentials and certificate decisions belong to the operator.
set -euo pipefail
umask 077
[[ $EUID == 0 && -t 0 ]] || { echo 'Run with sudo in an interactive SSM terminal.' >&2; exit 1; }
[[ $# == 4 ]] || { echo 'Usage: sudo bash install-server.sh PACKAGE.deb SHA256 SIGNING-KEY.gpg FINGERPRINT' >&2; exit 1; }
package=$(realpath "$1")
checksum=$2
key=$(realpath "$3")
fingerprint=${4^^}
[[ $checksum =~ ^[0-9a-fA-F]{64}$ && $fingerprint =~ ^[0-9A-F]{40}$ ]] || exit 1
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 && $(dpkg --print-architecture) == amd64 ]] || exit 1
mountpoint -q /srv/checkmk || { echo 'Prepare and mount the dedicated data disk first.' >&2; exit 1; }
printf '%s  %s\n' "$checksum" "$package" | sha256sum --check --status
verification_home=$(mktemp -d /run/checkmk-verification.XXXXXX)
trap 'rm -rf -- "$verification_home"' EXIT
gpg --homedir "$verification_home" --batch --import "$key"
actual_fingerprints=$(gpg --homedir "$verification_home" --with-colons --fingerprint | awk -F: '$1=="pub" {primary=1; next} $1=="fpr" && primary {print $10; primary=0}')
[[ $actual_fingerprints == "$fingerprint" ]] || { echo 'Signing key fingerprint mismatch.' >&2; exit 1; }
gpg --homedir "$verification_home" --batch --verify "$package"
[[ $(dpkg-deb -f "$package" Package) == check-mk-community-* ]] || { echo 'Expected the approved Community edition.' >&2; exit 1; }
[[ $(dpkg-deb -f "$package" Architecture) == amd64 ]] || exit 1
apt-get update
apt-get install -y "$package"
omd version
expected_version=$(dpkg-deb -f "$package" Package)
expected_version=${expected_version#check-mk-community-}
[[ $(omd version) == *"$expected_version.community"* ]] || {
  echo 'The default OMD version differs from the approved package. Select the approved Community version before site creation.' >&2; exit 1;
}

# Bind the complete sites directory to the attached volume before creating any site.
# Restoring an existing site is a separate procedure; never initialise over restored data.
if [[ -d /omd/sites/strathost/etc ]]; then
  echo 'Site exists. This script does not upgrade, move or reset it.'
  exit 0
fi
[[ -z $(find /omd/sites -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Existing sites require an explicit migration.' >&2; exit 1; }
mkdir -p /srv/checkmk/sites
[[ -z $(find /srv/checkmk/sites -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Restored site data found; use the recovery runbook.' >&2; exit 1; }
if ! findmnt --fstab --mountpoint /omd/sites >/dev/null; then
  printf '%s\n' '/srv/checkmk/sites /omd/sites none bind,x-systemd.requires-mounts-for=/srv/checkmk 0 0' >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q /omd/sites || mount /omd/sites
[[ $(findmnt -n -o UUID --target /omd/sites) == $(findmnt -n -o UUID --target /srv/checkmk) ]] || exit 1
mkdir -p /etc/systemd/system/omd.service.d
cat > /etc/systemd/system/omd.service.d/data-volume.conf <<'EOF'
[Unit]
RequiresMountsFor=/srv/checkmk /omd/sites
EOF
systemctl daemon-reload
# OMD prints a generated password. Capture it privately and replace it interactively.
creation_log=$(mktemp /run/checkmk-site-create.XXXXXX)
if ! omd create strathost > "$creation_log" 2>&1; then
  echo "Site creation failed. Inspect the root-only log: $creation_log" >&2; exit 1
fi
rm -- "$creation_log"
runuser -l strathost -c 'cmk-passwd cmkadmin'
runuser -l strathost -c 'omd start'
runuser -l strathost -c 'omd status'
echo 'Site created. Complete HTTPS, agent registration, discovery and notifications using the runbook.'
