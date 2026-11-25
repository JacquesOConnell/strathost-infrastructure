#!/usr/bin/env bash
# Runtime secret refresh also runs at boot. Values never enter Terraform or Docker environment variables.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 1 && $1 =~ ^(public_wordpress|secure_wordpress|internal_wordpress)$ ]] || exit 1
site=$1
config="/etc/strathost/wordpress/$site.json"
mountpoint -q "/srv/wordpress/$site/uploads" || exit 1
secret_arn=$(jq -er .secret_arn "$config")
install -d -m 0700 "/run/strathost/$site"
secret_file=$(mktemp "/run/strathost/$site/input.XXXXXX")
trap 'rm -f -- "$secret_file"' EXIT
aws secretsmanager get-secret-value --secret-id "$secret_arn" --region eu-west-1 --query SecretString --output text --no-cli-pager > "$secret_file"
for key in database_user database_password auth_key secure_auth_key logged_in_key nonce_key auth_salt secure_auth_salt logged_in_salt nonce_salt; do
  value=$(jq -er --arg key "$key" '.[$key] | select(type == "string" and length > 0 and (contains("\n") | not) and (contains("\r") | not))' "$secret_file")
  printf '%s' "$value" > "/run/strathost/$site/$key"
  # Container www-data needs read access; its parent on the host remains root-only.
  chmod 0444 "/run/strathost/$site/$key"
done
unset value
rm -- "$secret_file"
docker compose --env-file "/etc/strathost/wordpress/$site.env" -f /usr/local/lib/strathost/wordpress-compose.yaml -p "$site" config --quiet
docker compose --env-file "/etc/strathost/wordpress/$site.env" -f /usr/local/lib/strathost/wordpress-compose.yaml -p "$site" pull
# Refresh anonymous core/plugin files when replacing the pinned image; EFS uploads remain a bind mount.
docker compose --env-file "/etc/strathost/wordpress/$site.env" -f /usr/local/lib/strathost/wordpress-compose.yaml -p "$site" up -d --force-recreate --renew-anon-volumes
