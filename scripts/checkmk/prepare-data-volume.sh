#!/usr/bin/env bash
# Plan 14.4: mount the dedicated Checkmk EBS disk by UUID, never by an assumed /dev/sdf name.
set -euo pipefail
umask 077
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 && $1 =~ ^vol-[0-9a-f]{8,17}$ ]] || {
  echo 'Usage: sudo bash prepare-data-volume.sh vol-ID [--initialize-blank]' >&2; exit 1;
}
volume_id=$1
initialize=${2:-}
[[ -z $initialize || $initialize == --initialize-blank ]] || exit 1
device_link="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${volume_id//-/}"
[[ -b $device_link ]] || { echo 'Expected Nitro EBS device is not attached yet.' >&2; exit 1; }
device=$(readlink -f "$device_link")
# Refuse partitioned disks and any disk already mounted outside this intended location.
[[ $(lsblk -nr -o TYPE "$device") == disk ]] || { echo 'Refusing a partitioned device.' >&2; exit 1; }
mounted_at=$(findmnt -rn -S "$device" -o TARGET || true)
[[ -z $mounted_at || $mounted_at == /srv/checkmk ]] || { echo 'Device is already used elsewhere.' >&2; exit 1; }
filesystem=$(blkid -s TYPE -o value "$device" || true)
if [[ -z $filesystem ]]; then
  [[ $initialize == --initialize-blank ]] || { echo 'Blank disk: explicitly approve initialisation.' >&2; exit 1; }
  [[ -z $(wipefs --no-act --noheadings "$device") ]] || { echo 'Existing signatures found; refusing format.' >&2; exit 1; }
  mkfs.ext4 -L checkmk-data "$device"
elif [[ $filesystem != ext4 ]]; then
  echo 'Only an existing ext4 data filesystem is supported; nothing was formatted.' >&2; exit 1
fi
uuid=$(blkid -s UUID -o value "$device")
[[ $uuid =~ ^[0-9a-f-]{36}$ ]] || exit 1
mkdir -p /srv/checkmk
if ! mountpoint -q /srv/checkmk; then
  [[ -z $(find /srv/checkmk -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Mount would hide existing files.' >&2; exit 1; }
fi
entry="UUID=$uuid /srv/checkmk ext4 defaults,nofail 0 2"
if findmnt --fstab --mountpoint /srv/checkmk >/dev/null; then
  [[ $(findmnt --fstab --mountpoint /srv/checkmk -n -o SOURCE) == "UUID=$uuid" ]] || { echo 'Conflicting fstab entry.' >&2; exit 1; }
else
  cp --update=none /etc/fstab /etc/fstab.before-checkmk
  printf '%s\n' "$entry" >> /etc/fstab
fi
systemctl daemon-reload
mount /srv/checkmk
[[ $(findmnt -n -o UUID --target /srv/checkmk) == "$uuid" ]] || exit 1
findmnt /srv/checkmk
