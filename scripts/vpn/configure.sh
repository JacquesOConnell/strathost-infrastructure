#!/usr/bin/env bash
# Plan 17 / D04: single WireGuard appliance with HTTPS-only controlled SNAT.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 3 ]] || {
  echo 'Usage: sudo bash configure.sh WIREGUARD_PACKAGE_VERSION SERVER_SECRET_ARN APPROVED_PEERS.conf' >&2; exit 1;
}
package_version=$1
secret_arn=$2
peers=$(realpath "$3")
[[ $secret_arn =~ ^arn:aws:secretsmanager:eu-west-1:[0-9]{12}:secret: ]] || exit 1
command -v aws >/dev/null || { echo 'Install the approved AWS CLI first.' >&2; exit 1; }
[[ -f $peers && ! -L $peers && $(stat -c %u "$peers") == 0 ]] || { echo 'Peer inventory must be a root-owned regular file.' >&2; exit 1; }
# Only public peer keys and individual tunnel /32s are accepted; no executable PostUp hooks.
python3 - "$peers" <<'PY'
import base64, ipaddress, pathlib, sys
seen = set()
peer = {}
def validate():
    if set(peer) != {'PublicKey', 'AllowedIPs'}:
        raise SystemExit('Each peer requires exactly PublicKey and AllowedIPs')
    if len(base64.b64decode(peer['PublicKey'], validate=True)) != 32:
        raise SystemExit('Invalid peer public key')
    network = ipaddress.ip_network(peer['AllowedIPs'], strict=True)
    if network.prefixlen != 32 or network.network_address not in ipaddress.ip_network('10.250.0.0/24') or str(network.network_address) in {'10.250.0.0', '10.250.0.1', '10.250.0.255'} or str(network) in seen:
        raise SystemExit('Peers need distinct approved tunnel /32 addresses')
    seen.add(str(network))
for raw in pathlib.Path(sys.argv[1]).read_text().splitlines():
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    if line == '[Peer]':
        if peer:
            validate()
        peer = {}
    else:
        key, value = map(str.strip, line.split('=', 1))
        if key in peer or key not in {'PublicKey', 'AllowedIPs'}:
            raise SystemExit('Unsupported or duplicate peer setting')
        peer[key] = value
validate()
PY
apt-get update
apt-get install -y "wireguard=$package_version" iptables dnsmasq
install -d -m 0700 /etc/wireguard
private_key=$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --region eu-west-1 --query SecretString --output text --no-cli-pager)
[[ $private_key =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo 'Secret must contain only the WireGuard private key.' >&2; exit 1; }
printf '%s\n' "$private_key" | wg pubkey >/dev/null
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -m 0700 "$script_directory/firewall.sh" /usr/local/sbin/strathost-vpn-firewall
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.250.0.1/24
ListenPort = 51820
PrivateKey = $private_key
PostUp = /usr/local/sbin/strathost-vpn-firewall up %i
PostDown = /usr/local/sbin/strathost-vpn-firewall down %i
EOF
unset private_key
cat "$peers" >> /etc/wireguard/wg0.conf
chmod 0600 /etc/wireguard/wg0.conf
printf '%s\n' 'net.ipv4.ip_forward=1' > /etc/sysctl.d/90-strathost-vpn.conf
sysctl --system >/dev/null
# Private DNS uses only the tunnel listener; SGs do not expose a public resolver.
cat > /etc/dnsmasq.d/strathost.conf <<'EOF'
interface=wg0
listen-address=10.250.0.1
bind-dynamic
no-resolv
server=10.0.0.2
EOF
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
systemctl restart dnsmasq
wg show wg0 public-key
systemctl is-active wg-quick@wg0 dnsmasq
