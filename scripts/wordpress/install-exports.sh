#!/usr/bin/env bash
# Plan 18: daily logical exports are distinct from EC2/EFS recovery points and native RDS backups.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 1 && $1 =~ ^strathost-(dev|test|prod)-euw1-backup-[0-9]{12}$ ]] || exit 1
ip -4 -o address show | grep -q '10\.0\.4\.10/' || { echo 'Schedule exports only on Docker01.' >&2; exit 1; }
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -m 0700 "$script_directory/export-sites.py" /usr/local/lib/strathost/export-sites.py
printf '{"bucket":"%s"}\n' "$1" > /etc/strathost/wordpress/exports.json
cat > /etc/systemd/system/strathost-wordpress-exports.service <<'EOF'
[Unit]
Description=StratHost daily logical application exports
After=network-online.target docker.service
Requires=strathost-wordpress-public_wordpress.service strathost-wordpress-secure_wordpress.service strathost-wordpress-internal_wordpress.service
After=strathost-wordpress-public_wordpress.service strathost-wordpress-secure_wordpress.service strathost-wordpress-internal_wordpress.service
RequiresMountsFor=/srv/wordpress/public_wordpress/uploads /srv/wordpress/secure_wordpress/uploads /srv/wordpress/internal_wordpress/uploads

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/lib/strathost/export-sites.py
TimeoutStartSec=2h
EOF
cat > /etc/systemd/system/strathost-wordpress-exports.timer <<'EOF'
[Unit]
Description=Export StratHost databases and uploads daily

[Timer]
OnCalendar=*-*-* 00:10:00 UTC
Persistent=true
Unit=strathost-wordpress-exports.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now strathost-wordpress-exports.timer
