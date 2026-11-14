#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
cd "$REPO"
# shellcheck source=./held-packages-lib.sh
source "$DIR/held-packages-lib.sh"

# Root input names from flake.nix that `flake-update.sh` must leave alone.
# Flakes have no native per-input hold: `nix flake update` updates either
# every input or exactly the names given on the command line. This script
# passes the complement of this list, then prints the held pins.
HOLD_INPUTS=(
  # The frozen nixpkgs serving scripts/held-packages.nix (overlay:
  # modules/held-packages.nix). nixpkgs itself is NOT held anymore -
  # since the per-package hold machinery landed, a single known-bad
  # package freezes itself via `flake-rollback.sh --hold <pkg>` instead
  # of parking the whole distro pin (the old nixpkgs@f4a03c0 hold for
  # the zmx 1.0.1 SIGABRT).
  nixpkgs-held
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

# Package-level holds (scripts/held-packages.nix + modules/held-packages.nix):
# nixpkgs moves, these names do not. Print held vs current versions so a
# stale hold (nixpkgs caught up with the fixed version) is visible and can
# be released. Versions are best-effort nix evals - "?" on timeout/failure.
show_held_packages() {
  local names held_ref npkgs_ref pkg hv cv
  names=$(held_package_names)
  if [[ -z "${names// /}" ]]; then
    echo "Held packages: none (scripts/held-packages.nix is empty)."
    return
  fi
  held_ref=$(held_lock_ref nixpkgs-held)
  npkgs_ref=$(held_lock_ref nixpkgs)
  if [[ -z "$held_ref" ]]; then
    echo "Held packages [${names}]: ERROR - no nixpkgs-held input in flake.lock" >&2
    return
  fi
  echo "Held packages (overlaid from nixpkgs-held ${held_ref##*/}):"
  for pkg in $names; do
    hv=$(pkg_version "$held_ref" "$pkg")
    cv=$(pkg_version "$npkgs_ref" "$pkg")
    if [[ -z "$hv" ]]; then
      printf '  %-16s NOT IN nixpkgs-held - fix the hold or re-pin: scripts/flake-rollback.sh --hold %s [ref]\n' \
        "$pkg" "$pkg"
    elif [[ -z "$cv" ]]; then
      printf '  %-16s held %s -> gone from nixpkgs (decide: keep the anchor or drop it)\n' \
        "$pkg" "$hv"
    elif [[ "$hv" == "$cv" ]]; then
      printf '  %-16s held %s -> nixpkgs already there; release: scripts/flake-rollback.sh --release %s\n' \
        "$pkg" "$hv" "$pkg"
    else
      printf '  %-16s held %s -> nixpkgs would give %s\n' "$pkg" "$hv" "$cv"
    fi
  done
}

if ((${#to_update[@]} == 0)); then
  echo "All root inputs are held; nothing to update."
  show_held_packages
  exit 0
fi

echo "Updating: ${to_update[*]}"
if $dry_run; then
  show_held_packages
  exit 0
fi

# --commit-lock-file first, THEN report: "nixpkgs would give" must reflect
# the freshly locked nixpkgs, not the stale pin.
nix flake update "${to_update[@]}" --commit-lock-file
show_held_packages
