#!/usr/bin/env bash
set -euo pipefail

dir="${1:-$HOME/models/lfm2.5-vl-1.6b}"
base="https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/36fc16bc95133424921bcc3da009e83b2f23ffb5"

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

fetch LFM2.5-VL-1.6B-Q4_K_M.gguf \
  aefc3c97c9eb30d9c0dd6af4c38250f5f5106b57c8cf92de7914c7d0a9c94da2
fetch mmproj-LFM2.5-VL-1.6b-Q8_0.gguf \
  2ce89e610c56f3198ece2b86cf61743a08b9307279c89125eb2412ebb908689d
