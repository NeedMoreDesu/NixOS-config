#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
cd "$REPO"

usage() {
  echo "usage: $0 [OLD_REF]"
  echo
  echo "Compares flake.lock with OLD_REF's flake.lock and interactively restores"
  echo "selected root inputs to their OLD_REF pins."
  echo
  echo "OLD_REF defaults to the parent of the last commit that touched flake.lock"
  echo "(i.e. the state before the most recent lock update)."
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if (($# > 1)); then
  usage >&2
  exit 2
fi

if [[ -n "${1:-}" ]]; then
  OLD_REF=$1
else
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

if git diff --quiet -- flake.lock; then
  echo "No flake.lock changes."
  exit 0
fi

git --no-pager diff --stat -- flake.lock
printf 'Commit this rollback? [Y/n] '
if ! read -r commit_answer; then
  commit_answer=y
fi
if [[ "$commit_answer" =~ ^[Nn] ]]; then
  echo "Left flake.lock modified (not committed)."
  exit 0
fi

joined=$(IFS=,; echo "${selected[*]}")
git add flake.lock
git commit -m "flake.lock: roll back ${joined//,/, } to $OLD_SHORT"
