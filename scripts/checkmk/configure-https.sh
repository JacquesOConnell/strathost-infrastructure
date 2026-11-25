#!/usr/bin/env bash
# Plan 19: private UI access still needs a trusted TLS certificate.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 3 ]] || { echo 'Usage: sudo bash configure-https.sh FQDN FULLCHAIN.pem PRIVATE-KEY.pem' >&2; exit 1; }
server_name=$1
[[ $server_name =~ ^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$ ]] || exit 1
certificate=$(realpath "$2")
private_key=$(realpath "$3")
openssl x509 -in "$certificate" -noout -checkhost "$server_name"
openssl x509 -in "$certificate" -noout -checkend 604800
certificate_public=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum)
private_public=$(openssl pkey -in "$private_key" -pubout -outform DER | sha256sum)
[[ $certificate_public == "$private_public" ]] || { echo 'Certificate and key do not match.' >&2; exit 1; }
install -d -m 0700 /etc/strathost/tls
install -m 0644 "$certificate" /etc/strathost/tls/checkmk-fullchain.pem
install -m 0600 "$private_key" /etc/strathost/tls/checkmk-key.pem
cat > /etc/apache2/sites-available/strathost-checkmk.conf <<EOF
<VirtualHost *:443>
    ServerName $server_name
    SSLEngine on
    SSLProtocol -all +TLSv1.2 +TLSv1.3
    SSLCertificateFile /etc/strathost/tls/checkmk-fullchain.pem
    SSLCertificateKeyFile /etc/strathost/tls/checkmk-key.pem
    Header always set Strict-Transport-Security "max-age=31536000"
</VirtualHost>
EOF
# The package's global /omd/apache site configuration supplies the /strathost/ application alias.
a2enmod ssl headers
a2ensite strathost-checkmk
apache2ctl configtest
systemctl reload apache2
echo 'Test the private hostname and certificate from the VPN before relying on this endpoint.'
