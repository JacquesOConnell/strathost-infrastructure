#!/usr/bin/env bash
# Checkmk local-check format: state, quoted service, metrics, explanation.
# Install on all three Docker hosts after their EFS mounts have been configured.
set -u
for site in public_wordpress secure_wordpress internal_wordpress; do
  path="/srv/wordpress/$site/uploads"
  if mountpoint -q "$path"; then
    printf '0 "EFS %s mount" - Dedicated uploads mount is present\n' "$site"
  else
    printf '2 "EFS %s mount" - Uploads mount missing; prevent application startup\n' "$site"
  fi
done
