#!/usr/bin/env bash
# Plan 12 / D05: shared uploads only, using IAM-authenticated TLS access points.
set -euo pipefail
[[ $EUID == 0 && $# == 3 ]] || { echo 'Usage: sudo bash mount-uploads.sh SITE_KEY FILESYSTEM_ID ACCESS_POINT_ID' >&2; exit 1; }
site=$1
filesystem=$2
access_point=$3
[[ $site =~ ^(public_wordpress|secure_wordpress|internal_wordpress)$ && $filesystem =~ ^fs-[0-9a-f]+$ && $access_point =~ ^fsap-[0-9a-f]+$ ]] || exit 1
command -v mount.efs >/dev/null || { echo 'Install the approved efs-utils package first.' >&2; exit 1; }
path="/srv/wordpress/$site/uploads"
mkdir -p "$path"
if ! mountpoint -q "$path"; then
  [[ -z $(find "$path" -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Refusing to hide local uploads.' >&2; exit 1; }
fi
entry="$filesystem:/ $path efs _netdev,tls,iam,accesspoint=$access_point,noresvport 0 0"
if findmnt --fstab --mountpoint "$path" >/dev/null; then
  grep -Fxq "$entry" /etc/fstab || { echo 'Conflicting mount configuration.' >&2; exit 1; }
else
  printf '%s\n' "$entry" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$path" || mount "$path"
findmnt "$path"
