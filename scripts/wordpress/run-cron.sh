#!/usr/bin/env bash
# Plan 14: one scheduler avoids the three replicas running the same WordPress cron work.
set -euo pipefail
ip -4 -o address show | grep -q '10\.0\.4\.10/' || { echo 'Schedule only on Docker01.' >&2; exit 1; }
for site in public_wordpress secure_wordpress internal_wordpress; do
  docker compose --env-file "/etc/strathost/wordpress/$site.env" -f /usr/local/lib/strathost/wordpress-compose.yaml \
    -p "$site" exec -T --user www-data wordpress php /var/www/html/wp-cron.php
done
