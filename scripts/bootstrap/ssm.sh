#!/usr/bin/env bash
# Plan 14: official Canonical AMIs include the SSM snap. Do not curl-install an unpinned agent.
set -euo pipefail
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap start --enable amazon-ssm-agent
elif systemctl list-unit-files amazon-ssm-agent.service --no-legend | grep -q amazon-ssm-agent; then
  systemctl enable --now amazon-ssm-agent.service
else
  echo 'Pinned AMI lacks the required SSM agent; correct the image before provisioning.' >&2
  exit 1
fi
