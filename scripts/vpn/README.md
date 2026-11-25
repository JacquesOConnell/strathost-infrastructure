# WireGuard VPN configuration

I use one WireGuard server with a stable EIP, UDP 51820 and tunnel network `10.250.0.0/24`. Confirm non-overlap with client networks before use. Server source/destination checking is disabled by Terraform. Keys are generated outside Terraform and stored in the server-only Secrets Manager container; clients keep their own private keys. Approved public client CIDRs remain an independent security-group input.

Install the approved AWS CLI first. Generate/store the server private key using a secure operator workflow and protect the public peer inventory as a root-owned file. Each peer must have exactly its public key and a unique tunnel `/32`, for example:

```ini
[Peer]
PublicKey = REPLACE_WITH_CLIENT_PUBLIC_KEY
AllowedIPs = 10.250.0.2/32
```

```bash
apt-cache policy wireguard
sudo bash scripts/vpn/configure.sh APPROVED_WIREGUARD_PACKAGE_VERSION SERVER_SECRET_ARN /approved/peers.conf
sudo systemctl status wg-quick@wg0 dnsmasq
sudo wg show wg0 public-key
```

The script retrieves the raw base64 server key at runtime, writes a root-only configuration and enables forwarding. The separate `firewall.sh` permits only TCP 443 to application subnets `10.0.4/24`, `10.0.5/24`, `10.0.6/24` and Checkmk `10.0.3.30/32`, translating the source to `10.0.1.10`. Destination security groups further restrict access to the internal ALB and Checkmk. Tunnel traffic to other local server ports is dropped; only its DNS listener is allowed. Database subnets and general Internet transit are excluded. The script owns named chains and never flushes unrelated firewall rules.

dnsmasq listens only on `wg0`/`10.250.0.1` and forwards to the VPC resolver `10.0.0.2`. Use split-tunnel client routes for the three application subnets, Checkmk `/32` and tunnel DNS `/32`; set client DNS to `10.250.0.1`. The client endpoint is the VPN EIP on UDP 51820, with the server public key. Client key generation/import remains a local client operation. For clients behind NAT, review a 25-second PersistentKeepalive as needed.

Reconfiguration restarts the tunnel and briefly disconnects peers. Apply from SSM, preserve the prior protected configuration and peer inventory for rollback, and verify handshakes, private DNS and trusted HTTPS. Test blocked database/general-VPC/Internet forwarding and peer revocation. If a failed firewall operation leaves owned chains behind, inspect and repair those exact chains before restarting; do not broadly flush the host firewall. Verify any existing host firewall/dnsmasq configuration before taking ownership.

Only Bash syntax has been checked locally. Real Ubuntu installation, forwarding, DNS, reboot persistence and client connectivity remain deployment acceptance tests. The supplied single VPN server remains an availability dependency.

References: [WireGuard quick start](https://www.wireguard.com/quickstart/), [EC2 source/destination checks](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_NAT_Instance.html), [Secrets Manager access](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets.html).
