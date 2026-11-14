#!/usr/bin/env bash
# Copy trees into a user directory and remember what was installed, so the
# next run can remove stale copies before installing the new ones. The
# manifest is a tab-separated <dest-root>\t<tag>\t<name> file; entries for
# other roots/tags are preserved.
#
# Usage:
#   nix-copy-tree <manifest> <dest-root> <tag> <name> <source> [<name> <source> ...]
set -euo pipefail

if [ "$#" -lt 5 ] || [ $(( $# % 2 )) -ne 1 ]; then
  echo "usage: nix-copy-tree <manifest> <dest-root> <tag> <name> <source> [<name> <source> ...]" >&2
  exit 2
fi

manifest=$1
dest_root=$2
tag=$3
shift 3

case "$manifest" in
  /*) ;;
  *) echo "nix-copy-tree: manifest must be absolute: $manifest" >&2; exit 2 ;;
esac
case "$dest_root" in
  /*) ;;
  *) echo "nix-copy-tree: dest root must be absolute: $dest_root" >&2; exit 2 ;;
esac
dest_root=${dest_root%/}
if [ -z "$dest_root" ] || [ "$dest_root" = "/" ]; then
  echo "nix-copy-tree: refusing dest root: $dest_root" >&2
  exit 2
fi
case "$tag" in
  ""|*/*|.|..|*[[:space:]]*)
    echo "nix-copy-tree: bad tag: $tag" >&2
    exit 2
    ;;
esac

names=()
sources=()
while [ "$#" -gt 0 ]; do
  name=$1
  source=$2
  shift 2
  case "$name" in
    ""|*/*|.|..|*[[:space:]]*)
      echo "nix-copy-tree: bad name: $name" >&2
      exit 2
      ;;
  esac
  names+=("$name")
  sources+=("$source")
done

mkdir -p "$dest_root"
mkdir -p "$(dirname "$manifest")"

# Names this tag installed last time at this dest root.
declare -A old_names=()
if [ -f "$manifest" ]; then
  while IFS=$'\t' read -r old_root old_tag old_name; do
    [ -n "$old_root" ] || continue
    [ -n "$old_tag" ] || continue
    [ -n "$old_name" ] || continue
    [ "$old_root" = "$dest_root" ] || continue
    [ "$old_tag" = "$tag" ] || continue
    old_names["$old_name"]=1
  done < "$manifest"
fi

# Refuse to clobber a path this tag did not install.
i=0
while [ "$i" -lt "${#names[@]}" ]; do
  name=${names[$i]}
  if { [ -e "$dest_root/$name" ] || [ -L "$dest_root/$name" ]; } &&
    [ -z "${old_names[$name]:-}" ]; then
    echo "nix-copy-tree: refusing to overwrite unmanaged $dest_root/$name" >&2
    exit 1
  fi
  i=$((i + 1))
done

# Stage first: a failed copy must leave the old trees alone.
stage=$(mktemp -d "$dest_root/.nix-copy-tree.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT

i=0
while [ "$i" -lt "${#names[@]}" ]; do
  cp -r -- "${sources[$i]}" "$stage/${names[$i]}"
  chmod -R u+rwX -- "$stage/${names[$i]}"
  i=$((i + 1))
done

# Drop the previous copies owned by this root+tag.
if [ -f "$manifest" ]; then
  while IFS=$'\t' read -r old_root old_tag old_name; do
    [ -n "$old_root" ] || continue
    [ -n "$old_tag" ] || continue
    [ -n "$old_name" ] || continue
    [ "$old_root" = "$dest_root" ] || continue
    [ "$old_tag" = "$tag" ] || continue
    rm -rf -- "$dest_root/$old_name"
  done < "$manifest"
fi

# Swap the staged trees in.
i=0
while [ "$i" -lt "${#names[@]}" ]; do
  rm -rf -- "$dest_root/${names[$i]}"
  mv -- "$stage/${names[$i]}" "$dest_root/${names[$i]}"
  i=$((i + 1))
done

# Rewrite the manifest atomically: keep other roots/tags, replace ours.
tmp=$(mktemp "$manifest.XXXXXX")
if [ -f "$manifest" ]; then
  while IFS=$'\t' read -r old_root old_tag old_name; do
    [ -n "$old_root" ] || continue
    [ -n "$old_tag" ] || continue
    [ -n "$old_name" ] || continue
    if [ "$old_root" = "$dest_root" ] && [ "$old_tag" = "$tag" ]; then
      continue
    fi
    printf '%s\t%s\t%s\n' "$old_root" "$old_tag" "$old_name" >> "$tmp"
  done < "$manifest"
fi
i=0
while [ "$i" -lt "${#names[@]}" ]; do
  printf '%s\t%s\t%s\n' "$dest_root" "$tag" "${names[$i]}" >> "$tmp"
  i=$((i + 1))
done
mv -- "$tmp" "$manifest"
