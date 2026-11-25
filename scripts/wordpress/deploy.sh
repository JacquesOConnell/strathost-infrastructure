#!/usr/bin/env bash
# Plan 12/14: one site, repeated on all three fixed Docker hosts after target draining.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 1 ]] || { echo 'Usage: sudo bash deploy.sh /approved/site.json' >&2; exit 1; }
config=$(realpath "$1")
[[ -f $config && ! -L $config && $(stat -c %u "$config") == 0 ]] || exit 1
site=$(jq -er .site "$config")
case "$site" in
  public_wordpress) port=8080; visibility=public ;;
  secure_wordpress) port=8081; visibility=secure ;;
  internal_wordpress) port=8082; visibility=internal ;;
  *) exit 1 ;;
esac
hostname=$(jq -er .hostname "$config")
private_ip=$(jq -er .private_ip "$config")
database_host=$(jq -er .database_host "$config")
database_name=$(jq -er .database_name "$config")
secret_arn=$(jq -er .secret_arn "$config")
wordpress_image=$(jq -er .wordpress_image "$config")
nginx_image=$(jq -er .nginx_image "$config")
rds_ca_file=$(jq -er .rds_ca_file "$config")
issuer=$(jq -r '.access_issuer // ""' "$config")
audience=$(jq -r '.access_audience // ""' "$config")
memory_limit=$(jq -r '.wordpress_memory_limit // "512m"' "$config")
[[ $memory_limit =~ ^[1-9][0-9]{1,4}m$ ]] || exit 1
[[ $hostname =~ ^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$ && $private_ip =~ ^10\.0\.[456]\.10$ ]] || exit 1
[[ $database_host =~ ^[a-z0-9.-]+\.eu-west-1\.rds\.amazonaws\.com$ && $database_name =~ ^[a-z][a-z0-9_]{0,63}$ ]] || exit 1
[[ $wordpress_image =~ ^[a-zA-Z0-9./_-]+@sha256:[0-9a-f]{64}$ && $nginx_image =~ ^[a-zA-Z0-9./_-]+@sha256:[0-9a-f]{64}$ ]] || exit 1
[[ $rds_ca_file =~ ^/[a-zA-Z0-9/_.-]+$ && -r $rds_ca_file && $secret_arn =~ ^arn:aws:secretsmanager:eu-west-1:[0-9]{12}:secret: ]] || exit 1
if [[ $visibility == secure ]]; then
  [[ $issuer =~ ^https://[a-z0-9-]+\.cloudflareaccess\.com$ && $audience =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Secure origin needs the exact Access issuer and audience.' >&2; exit 1; }
else
  issuer=''; audience=''
fi
uploads="/srv/wordpress/$site/uploads"
mountpoint -q "$uploads" || { echo 'EFS mount missing; refusing local fallback.' >&2; exit 1; }
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -d -m 0700 /etc/strathost/wordpress /usr/local/lib/strathost
install -m 0644 "$script_directory/compose.yaml" /usr/local/lib/strathost/wordpress-compose.yaml
install -m 0700 "$script_directory/start-site.sh" /usr/local/lib/strathost/start-wordpress-site
if [[ $config != "/etc/strathost/wordpress/$site.json" ]]; then
  install -m 0600 "$config" "/etc/strathost/wordpress/$site.json"
fi
install -d -m 0700 "/etc/strathost/wordpress/$site"
cat > "/etc/strathost/wordpress/$site/proxy.conf" <<EOF
server {
    listen 8080 default_server;
    server_name _;
    location = /healthz {
        proxy_pass http://wordpress:80/strathost-health.php;
        proxy_connect_timeout 2s;
        proxy_read_timeout 3s;
    }
    location / { return 403; }
}
server {
    listen 8080;
    server_name $hostname;
    client_max_body_size 32m;
    location ^~ /healthz { return 403; }
    location ^~ /strathost-health.php { return 403; }
    location / {
        proxy_pass http://wordpress:80;
        proxy_set_header Host $hostname;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Cf-Access-Authenticated-User-Email "";
    }
}
EOF
# Environment contains identifiers only. Passwords and salts are read from root-owned tmpfs files.
cat > "/etc/strathost/wordpress/$site.env" <<EOF
WORDPRESS_IMAGE=$wordpress_image
NGINX_IMAGE=$nginx_image
WORDPRESS_MEMORY_LIMIT=$memory_limit
DATABASE_HOST=$database_host
DATABASE_NAME=$database_name
SITE_HOSTNAME=$hostname
PRIVATE_IP=$private_ip
PROXY_PORT=$port
VISIBILITY=$visibility
ACCESS_ISSUER=$issuer
ACCESS_AUDIENCE=$audience
UPLOADS_PATH=$uploads
RDS_CA_FILE=$rds_ca_file
PROXY_CONFIG=/etc/strathost/wordpress/$site/proxy.conf
SECRETS_DIRECTORY=/run/strathost/$site
EOF
cat > "/etc/systemd/system/strathost-wordpress-$site.service" <<EOF
[Unit]
Description=StratHost WordPress $site
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
RequiresMountsFor=$uploads

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/lib/strathost/start-wordpress-site $site
ExecStop=/usr/bin/docker compose --env-file /etc/strathost/wordpress/$site.env -f /usr/local/lib/strathost/wordpress-compose.yaml -p $site down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "strathost-wordpress-$site"
systemctl restart "strathost-wordpress-$site"
echo 'Verify readiness, application login and target health before re-registering this host.'
