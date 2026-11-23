#!/usr/bin/env bash
set -euo pipefail

# Root-layout GGUFs for Unsloth's llama.cpp prebuilt (not Mainline_Support).
# Revision is pinned; every file is sha256-checked before it is moved into
# place. DSpark is optional and only fetched with --dspark.
rev="800c946d7b9c830c86290df49afbbe91db8455f5"
base="https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/$rev"

dspark=false
while (($#)); do
  case "$1" in
    --dspark) dspark=true ;;
    -h | --help)
      echo "usage: fetch-inkling [--dspark] [DIR]"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "fetch-inkling: unknown option: $1" >&2
      exit 2
      ;;
    *) break ;;
  esac
  shift
done

dir="${1:-$HOME/models/inkling-2-mini}"
mkdir -p "$dir"

fetch() {
  local name="$1" sha="$2"
  if [[ -f "$dir/$name" ]] && echo "$sha  $dir/$name" | sha256sum -c --status; then
    echo "ok: $name"
    return
  fi
  echo "fetching: $name"
  curl -fL --retry 5 --retry-delay 2 -o "$dir/$name.part" "$base/$name"
  echo "$sha  $dir/$name.part" | sha256sum -c -
  mv "$dir/$name.part" "$dir/$name"
}

fetch Inkling-2-Mini-UD-Q4_K_M.gguf \
  f90c5a4df44d335ac9f9eea2a15c31d6c5a377b1b3cd9ff7fc2cf123f3cdf7e1
fetch mmproj-F16.gguf \
  3bff75ffeb2d6e0371ba7bd42e30d26a7d98aea681fa44b03b5a20891cfa2c5f

if $dspark; then
  fetch dspark-Inkling-2-Mini-Q8_0.gguf \
    2ec78510da837e8fc3be54a14757a0c5fbd2d8d9e85a0d92853fafdf674f3773
fi
