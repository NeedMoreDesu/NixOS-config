#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# Run nixos-rebuild against the repo config (script is executed via sudo).
nixos-rebuild switch -I nixos-config="$REPO/configuration.nix"
