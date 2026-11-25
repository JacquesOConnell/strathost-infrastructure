#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
ip -4 -o address show | grep -q '10\.0\.4\.10/' || { echo 'Install the timer only on Docker01.' >&2; exit 1; }
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -m 0700 "$script_directory/run-cron.sh" /usr/local/lib/strathost/wordpress-cron
cat > /etc/systemd/system/strathost-wordpress-cron.service <<'EOF'
[Unit]
Description=StratHost single WordPress cron scheduler
After=docker.service network-online.target
Requires=strathost-wordpress-public_wordpress.service strathost-wordpress-secure_wordpress.service strathost-wordpress-internal_wordpress.service
After=strathost-wordpress-public_wordpress.service strathost-wordpress-secure_wordpress.service strathost-wordpress-internal_wordpress.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/strathost/wordpress-cron
EOF
cat > /etc/systemd/system/strathost-wordpress-cron.timer <<'EOF'
[Unit]
Description=Run due WordPress cron events every five minutes

[Timer]
OnCalendar=*:0/5
Persistent=true
Unit=strathost-wordpress-cron.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now strathost-wordpress-cron.timer
