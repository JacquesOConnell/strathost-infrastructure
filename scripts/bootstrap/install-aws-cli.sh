#!/usr/bin/env bash
# Runtime AWS calls use temporary instance-profile credentials. Pin and verify the CLI artifact first.
set -euo pipefail
umask 077
[[ $EUID == 0 && $# == 6 ]] || {
  echo 'Usage: sudo bash install-aws-cli.sh CLI.zip SHA256 CLI.zip.sig PUBLIC-KEY.gpg KEY_FINGERPRINT EXPECTED_VERSION' >&2; exit 1;
}
archive=$(realpath "$1")
checksum=$2
signature=$(realpath "$3")
key=$(realpath "$4")
fingerprint=${5^^}
version=$6
[[ $checksum =~ ^[0-9a-fA-F]{64}$ && $fingerprint =~ ^[0-9A-F]{40}$ && $version =~ ^2\.[0-9]+\.[0-9]+$ && $(uname -m) == x86_64 ]] || exit 1
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
apt-get update
apt-get install -y gnupg unzip
temporary=$(mktemp -d /run/strathost-aws-cli.XXXXXX)
trap 'rm -rf -- "$temporary"' EXIT
install -d -m 0700 "$temporary/gnupg"
gpg --homedir "$temporary/gnupg" --batch --import "$key"
actual_fingerprint=$(gpg --homedir "$temporary/gnupg" --with-colons --fingerprint | awk -F: '$1=="pub" {primary=1; next} $1=="fpr" && primary {print $10; primary=0}')
[[ $actual_fingerprint == "$fingerprint" ]] || exit 1
gpg --homedir "$temporary/gnupg" --batch --verify "$signature" "$archive"
unzip -q "$archive" -d "$temporary"
"$temporary/aws/install" --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
[[ $(/usr/local/bin/aws --version) == "aws-cli/$version "* ]] || { echo 'Installed CLI does not match the approved version.' >&2; exit 1; }
/usr/local/bin/aws --version
