#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

exec nixos-rebuild switch --flake "$REPO#nixos"
