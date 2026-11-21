#!/usr/bin/env bash
set -euo pipefail

dir="${1:-$HOME/models/embeddinggemma-2}"
base="https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71"

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

fetch embeddinggemma-2-Q8_0.gguf \
  2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135
fetch mmproj-embeddinggemma-2-Q8_0.gguf \
  0531309472a6bc6f4b146c3736eee7795ec9db1903c25490d3c937490cef6dd8
