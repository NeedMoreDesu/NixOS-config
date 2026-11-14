#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
cd "$REPO"
# shellcheck source=./held-packages-lib.sh
source "$DIR/held-packages-lib.sh"

usage() {
  cat <<EOF
usage: $0 [OLD_REF]                roll back flake.lock INPUT pins
       $0 --hold PKG [OLD_REF]     freeze one nixpkgs package
       $0 --release PKG            unfreeze one nixpkgs package

Input rollback (default): compares flake.lock with OLD_REF's flake.lock
and interactively restores selected root inputs to their OLD_REF pins.
OLD_REF defaults to the parent of the last commit that touched flake.lock
(i.e. the state before the most recent lock update).

--hold/--release are the per-package counterpart, for the case "the
nixpkgs update moved ONE bad package" (scripts/held-packages.nix +
modules/held-packages.nix):
  --hold PKG re-pins the nixpkgs-held input to OLD_REF's nixpkgs rev
     (default: the last known-good lock parent) and adds PKG to
     scripts/held-packages.nix, so PKG serves the old version while
     nixpkgs itself stays current. PKG must exist in nixpkgs at that
     rev; only do this for standalone binaries.
  --release PKG drops PKG from the hold list (it follows nixpkgs
     again). nixpkgs-held stays parked as the fallback anchor; drop
     the input from flake.nix + flake-update.sh's HOLD_INPUTS when the
     list goes empty.
EOF
}

mode=inputs
pkg=""
ref_arg=""
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --hold | --release)
    mode=${1#--}
    if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
      echo "error: --$mode needs a package name" >&2
      usage >&2
      exit 2
    fi
    pkg=$2
    ref_arg=${3:-}
    ;;
esac
if [[ $mode == inputs ]]; then
  if (($# > 1)); then
    usage >&2
    exit 2
  fi
  ref_arg=${1:-}
fi

resolve_old_ref() {
  if [[ -n "$ref_arg" ]]; then
    OLD_REF=$ref_arg
  else
    local last
    last=$(git log -1 --format=%H -- flake.lock)
    if [[ -z "$last" ]]; then
      echo "error: flake.lock has no git history" >&2
      exit 1
    fi
    OLD_REF="${last}^"
  fi
  if ! git rev-parse --verify --quiet "$OLD_REF" >/dev/null; then
    echo "error: not a valid git ref: $OLD_REF" >&2
    exit 2
  fi
  OLD_SHORT=$(git rev-parse --short "$OLD_REF")
}

confirm_commit() {
  local msg=$1
  shift
  if git diff --cached --quiet -- "$@"; then
    echo "Nothing staged; leaving changes uncommitted."
    exit 0
  fi
  git --no-pager diff --cached --stat -- "$@"
  printf 'Commit? [Y/n] '
  local answer
  if ! read -r answer; then
    answer=y
  fi
  if [[ "$answer" =~ ^[Nn] ]]; then
    echo "Left changes staged but uncommitted."
    exit 0
  fi
  git commit -m "$msg"
}

# ---- --release: no old-ref needed, just edit the hold list ----
if [[ $mode == release ]]; then
  if ! grep -qw -- "$pkg" <<<"$(held_package_names)"; then
    echo "error: '$pkg' is not held (scripts/held-packages.nix)" >&2
    exit 1
  fi
  # Match the ENTRY line ("pkg" possibly followed by inline comment) -
  # never the #comment lines above it. ($ only anchors at end of pattern.)
  sed -i -E "/^[[:space:]]*\"${pkg}\"[[:space:]]*(#.*)?$/d" "$HELD_PACKAGES_FILE"
  echo "Released $pkg: it follows nixpkgs again after the next rebuild."
  npkgs_v=$(pkg_version "$(held_lock_ref nixpkgs)" "$pkg")
  [[ -n "$npkgs_v" ]] && echo "  nixpkgs currently serves $pkg $npkgs_v"
  left=$(held_package_names)
  if [[ -z "${left// /}" ]]; then
    echo "  Hold list is now EMPTY: nixpkgs-held is dead weight - drop the input"
    echo "  from flake.nix + flake-update.sh's HOLD_INPUTS when convenient."
  fi
  git add -- scripts/held-packages.nix
  confirm_commit "flake: release $pkg (back on live nixpkgs)" -- scripts/held-packages.nix
  exit 0
fi

resolve_old_ref

lock_info() {
  local lock=$1
  nix eval --impure --raw \
    --expr "(import \"$DIR/flake-lock-info.nix\" { lockPath = \"$lock\"; })" \
    --apply 'x: builtins.concatStringsSep "\n" (x ++ [""])'
}

declare -A version_cache
flake_version() {
  local ref=$1 name=$2 key="$1|$2"
  if [[ -v version_cache[$key] ]]; then
    printf '%s' "${version_cache[$key]}"
    return
  fi
  local value
  value=$(timeout 25 nix eval --impure --raw \
    --expr "(import \"$DIR/flake-version.nix\" { flakeRef = \"$ref\"; name = \"$name\"; })" \
    2>/dev/null) || value=""
  version_cache[$key]=$value
  printf '%s' "$value"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
git show "$OLD_REF:flake.lock" >"$tmpdir/old.lock"
cp flake.lock "$tmpdir/current.lock"

declare -A old_rev old_date old_ref cur_rev cur_date cur_ref
while IFS=$'\t' read -r name rev ts ref; do
  [[ -z "$name" ]] && continue
  old_rev[$name]=$rev
  old_date[$name]=$ts
  old_ref[$name]=$ref
done < <(lock_info "$tmpdir/old.lock")
while IFS=$'\t' read -r name rev ts ref; do
  [[ -z "$name" ]] && continue
  cur_rev[$name]=$rev
  cur_date[$name]=$ts
  cur_ref[$name]=$ref
done < <(lock_info "$tmpdir/current.lock")

# Package holds are orthogonal to input pins (frozen packages survive any
# input rollback), but always visible here so rollback decisions see them.
holds=$(held_package_names)
if [[ -n "${holds// /}" ]]; then
  echo "Package holds (served by nixpkgs-held ${cur_rev[nixpkgs-held]:-MISSING}; input rollback does NOT touch these):"
  for p in $holds; do
    hv=$(pkg_version "${cur_ref[nixpkgs-held]:-}" "$p")
    cv=$(pkg_version "${cur_ref[nixpkgs]:-}" "$p")
    note=""
    [[ -n "$hv" && "$hv" == "$cv" ]] && note="  (redundant: $0 --release $p)"
    printf '  %-16s held %s | nixpkgs %s%s\n' "$p" "${hv:-?}" "${cv:-?}" "$note"
  done
  echo
fi

# ---- --hold: freeze PKG by re-pinning nixpkgs-held + editing the list ----
if [[ $mode == hold ]]; then
  if grep -qw -- "$pkg" <<<"$holds"; then
    echo "error: '$pkg' is already held (scripts/held-packages.nix)" >&2
    exit 1
  fi
  old_np=${old_ref[nixpkgs]:-}
  if [[ -z "$old_np" ]]; then
    echo "error: nixpkgs is not a locked root input at $OLD_SHORT" >&2
    exit 1
  fi
  old_v=$(pkg_version "$old_np" "$pkg")
  if [[ -z "$old_v" ]]; then
    echo "error: '$pkg' not found in nixpkgs at $OLD_SHORT - pick a ref that has it" >&2
    exit 1
  fi
  cur_v=$(pkg_version "${cur_ref[nixpkgs]:-}" "$pkg")
  held_pin=${cur_ref[nixpkgs-held]:-}
  echo "Hold $pkg at nixpkgs ${old_rev[nixpkgs]:0:12} ($OLD_SHORT): version $old_v"
  if [[ -n "$cur_v" ]]; then
    if [[ "$cur_v" == "$old_v" ]]; then
      echo "  WARNING: current nixpkgs already has $cur_v - the hold would be redundant."
    else
      echo "  current nixpkgs ${cur_rev[nixpkgs]:0:12} has $cur_v"
    fi
  else
    echo "  $pkg is gone from current nixpkgs (hold resurrects the old build)"
  fi
  if [[ -n "${holds// /}" && "$held_pin" != "$old_np" ]]; then
    echo "  NOTE: nixpkgs-held re-pins ${held_pin##*/} -> ${old_np##*/};"
    echo "  every hold shares this one anchor, existing entries move too:"
    for p in $holds; do
      printf '    %-16s -> %s\n' "$p" "$(pkg_version "$old_np" "$p")"
    done
  fi
  if [[ "$held_pin" != "$old_np" ]]; then
    echo "Re-locking nixpkgs-held -> ${old_rev[nixpkgs]:0:12}"
    nix flake lock --override-input nixpkgs-held "$old_np"
  else
    echo "nixpkgs-held already pinned at ${old_np##*/}; only the list changes."
  fi
  sed -i -E "0,/^]/s/^]/  \"$pkg\"  # held $(date +%F) from ${old_rev[nixpkgs]:0:12} (flake-rollback.sh --hold)\\n]/" "$HELD_PACKAGES_FILE"
  git add -- scripts/held-packages.nix flake.lock
  confirm_commit "flake: hold $pkg at nixpkgs ${old_rev[nixpkgs]:0:12}" -- scripts/held-packages.nix flake.lock
  exit 0
fi

# ---- default mode: interactive input-pin rollback ----
changed=()
while IFS= read -r name; do
  [[ -n "${cur_rev[$name]:-}" ]] || continue
  [[ "${old_rev[$name]}" != "${cur_rev[$name]}" ]] || continue
  changed+=("$name")
done < <(printf '%s\n' "${!old_rev[@]}" | sort)

if ((${#changed[@]} == 0)); then
  echo "No root-input pin changes between $OLD_SHORT and the working flake.lock."
  exit 0
fi

declare -A old_ver new_ver
printf 'Resolving versions (best effort)...\n' >&2
for name in "${changed[@]}"; do
  old_ver[$name]=$(flake_version "${old_ref[$name]}" "$name")
  new_ver[$name]=$(flake_version "${cur_ref[$name]}" "$name")
done

echo "Pin changes: $OLD_SHORT -> working tree"
i=0
for name in "${changed[@]}"; do
  i=$((i + 1))
  printf '%2d) %-16s %s' "$i" "$name" "${old_rev[$name]:0:12}"
  if [[ "${old_date[$name]}" != 0 ]]; then
    printf ' (%s)' "$(date -d "@${old_date[$name]}" +%Y-%m-%d)"
  fi
  printf ' -> %s' "${cur_rev[$name]:0:12}"
  if [[ "${cur_date[$name]}" != 0 ]]; then
    printf ' (%s)' "$(date -d "@${cur_date[$name]}" +%Y-%m-%d)"
  fi
  printf '\n'
  if [[ -n "${old_ver[$name]}" || -n "${new_ver[$name]}" ]]; then
    printf '    %-16s %s -> %s\n' "version" "${old_ver[$name]:-?}" "${new_ver[$name]:-?}"
  fi
done

echo
printf 'Roll back which inputs to %s pins? [e.g. 1 3; a=all; enter=quit] ' "$OLD_SHORT"
if ! read -r answer; then
  exit 0
fi
case "$answer" in
  "" | q | quit) exit 0 ;;
esac

selected=()
if [[ "$answer" == a || "$answer" == all ]]; then
  selected=("${changed[@]}")
else
  for token in $answer; do
    if ! [[ "$token" =~ ^[0-9]+$ ]] || ((token < 1 || token > ${#changed[@]})); then
      echo "invalid selection: $token" >&2
      exit 2
    fi
    selected+=("${changed[$((token - 1))]}")
  done
fi

args=()
for name in "${selected[@]}"; do
  args+=(--override-input "$name" "${old_ref[$name]}")
done

echo "Re-locking: ${selected[*]} -> $OLD_SHORT"
nix flake lock "${args[@]}"

git add -- flake.lock
confirm_commit "$(
  joined=$(IFS=,; echo "${selected[*]}")
  echo "flake.lock: roll back ${joined//,/, } to $OLD_SHORT"
)" -- flake.lock
