#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
cd "$REPO"

# Root input names from flake.nix that `flake-update.sh` must leave alone.
# Flakes have no native per-input hold: `nix flake update` updates either
# every input or exactly the names given on the command line. This script
# passes the complement of this list, then prints the held pins.
HOLD_INPUTS=(
  # zmx 1.0.1 (nixpkgs) SIGABRTs on every daemon shutdown, i.e. every
  # zmx kill / cleanup shortcut. 0.8.1 (this pin) is clean. Upstream fix
  # is f5d604e on zmx main (PR #316), not released/packaged yet.
  nixpkgs
)

dry_run=false
case "${1:-}" in
  -n | --dry-run) dry_run=true ;;
  "") ;;
  *)
    echo "usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

lock_info() {
  local lock=$1
  nix eval --impure --raw \
    --expr "(import \"$DIR/flake-lock-info.nix\" { lockPath = \"$lock\"; })" \
    --apply 'x: builtins.concatStringsSep "\n" (x ++ [""])'
}

declare -A rev_for date_for
root_inputs=()
while IFS=$'\t' read -r name rev ts _ref; do
  [[ -z "$name" ]] && continue
  root_inputs+=("$name")
  rev_for[$name]=$rev
  date_for[$name]=$ts
done < <(lock_info "$REPO/flake.lock")

is_held() {
  local name=$1 hold
  for hold in "${HOLD_INPUTS[@]}"; do
    [[ "$hold" == "$name" ]] && return 0
  done
  return 1
}

to_update=()
for name in "${root_inputs[@]}"; do
  is_held "$name" || to_update+=("$name")
done

for hold in "${HOLD_INPUTS[@]}"; do
  if [[ -z "${rev_for[$hold]:-}" ]]; then
    echo "warning: hold '$hold' is not a root input in flake.nix" >&2
  fi
done

if ((${#HOLD_INPUTS[@]})); then
  echo "Held (kept at their locked pins):"
  for hold in "${HOLD_INPUTS[@]}"; do
    [[ -n "${rev_for[$hold]:-}" ]] || continue
    printf '  %-16s %s' "$hold" "${rev_for[$hold]:0:12}"
    if [[ "${date_for[$hold]}" != 0 ]]; then
      printf '  (%s)' "$(date -d "@${date_for[$hold]}" +%Y-%m-%d)"
    fi
    printf '\n'
  done
fi

if ((${#to_update[@]} == 0)); then
  echo "All root inputs are held; nothing to update."
  exit 0
fi

echo "Updating: ${to_update[*]}"
if $dry_run; then
  exit 0
fi

nix flake update "${to_update[@]}" --commit-lock-file
