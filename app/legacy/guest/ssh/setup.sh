#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" != 0 ]; then
  echo "Run this setup with sudo."
  exit 1
fi
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
destination=$(mktemp -d /etc/nixos/ohmansy-ssh.XXXXXX)
chmod 755 "$destination"
install -m 644 "$source_dir/configuration.nix" "$source_dir/id_ed25519.pub" "$destination/"
nixos-rebuild switch -I "nixos-config=$destination/configuration.nix"
echo "SSH is ready. Configuration: $destination/configuration.nix"
echo "Host key fingerprint:"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
