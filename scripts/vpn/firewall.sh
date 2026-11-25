#!/usr/bin/env bash
# Plan 17: only private HTTPS to application subnets and Checkmk may cross the tunnel.
# Destination security groups further restrict this to the internal ALB and Checkmk.
set -euo pipefail
[[ $EUID == 0 && $# == 2 && $1 =~ ^(up|down)$ && $2 =~ ^[a-zA-Z0-9]+$ ]] || exit 1
action=$1
tunnel=$2
interface=$(ip -4 route show default | awk 'NR==1 {print $5}')
[[ $interface =~ ^[a-zA-Z0-9]+$ ]] || exit 1
if [[ $action == up ]]; then
  iptables -N STRATHOST_VPN
  iptables -N STRATHOST_VPN_INPUT
  iptables -I INPUT 1 -i "$tunnel" -j STRATHOST_VPN_INPUT
  iptables -A STRATHOST_VPN_INPUT -p udp --dport 53 -j ACCEPT
  iptables -A STRATHOST_VPN_INPUT -p tcp --dport 53 -j ACCEPT
  iptables -A STRATHOST_VPN_INPUT -j DROP
  # Insert ahead of existing forwarding rules so unrelated rules cannot bypass the tunnel boundary.
  iptables -I FORWARD 1 -i "$tunnel" -j STRATHOST_VPN
  iptables -I FORWARD 1 -o "$tunnel" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  for destination in 10.0.4.0/24 10.0.5.0/24 10.0.6.0/24 10.0.3.30/32; do
    iptables -A STRATHOST_VPN -d "$destination" -p tcp --dport 443 -j ACCEPT
    iptables -t nat -A POSTROUTING -s 10.250.0.0/24 -d "$destination" -p tcp --dport 443 -o "$interface" -j SNAT --to-source 10.0.1.10
  done
  iptables -A STRATHOST_VPN -j DROP
else
  iptables -D INPUT -i "$tunnel" -j STRATHOST_VPN_INPUT
  iptables -F STRATHOST_VPN_INPUT
  iptables -X STRATHOST_VPN_INPUT
  iptables -D FORWARD -i "$tunnel" -j STRATHOST_VPN
  iptables -D FORWARD -o "$tunnel" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  for destination in 10.0.4.0/24 10.0.5.0/24 10.0.6.0/24 10.0.3.30/32; do
    iptables -t nat -D POSTROUTING -s 10.250.0.0/24 -d "$destination" -p tcp --dport 443 -o "$interface" -j SNAT --to-source 10.0.1.10
  done
  iptables -F STRATHOST_VPN
  iptables -X STRATHOST_VPN
fi
