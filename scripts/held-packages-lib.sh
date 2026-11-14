# Shared helpers for the per-package holds (scripts/held-packages.nix
# list + modules/held-packages.nix overlay). Sourced by
# flake-update.sh and flake-rollback.sh - not executable on its own.
# The caller must set REPO (path of the flake repo root).

HELD_PACKAGES_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/held-packages.nix"

NIX_SYSTEM=${NIX_SYSTEM:-$(nix eval --raw --impure --expr 'builtins.currentSystem')}

# Held package names from the list file, whitespace-separated; "" if none.
held_package_names() {
  nix eval --impure --raw \
    --expr "builtins.concatStringsSep \" \" (import \"$HELD_PACKAGES_FILE\")" \
    2>/dev/null
}

# Locked flake-ref (4th lock-info field) of a ROOT input in the working
# flake.lock; "" if the input is not in the lock.
held_lock_ref() {
  nix eval --impure --raw \
    --expr "(import \"$(dirname "${BASH_SOURCE[0]}")/flake-lock-info.nix\" { lockPath = \"$REPO/flake.lock\"; })" \
    --apply 'rows: builtins.concatStringsSep "\n" (rows ++ [""])' 2>/dev/null |
    awk -F '\t' -v n="$1" '$1 == n { print $4 }'
}

# Best-effort version of a nixpkgs attribute at a flake-ref: .version,
# else the derivation name with the pname prefix stripped. "" on any
# failure (missing package, eval error, timeout). Generous timeout:
# forcing legacyPackages.<name> evaluates the whole package set of a
# tree, which is slow but cached by the daemon afterwards.
pkg_version() {
  local ref=$1 name=$2 v
  [[ -n "$ref" ]] || { printf ''; return; }
  v=$(timeout 180 nix eval --impure --raw \
    --expr "let p = (builtins.getFlake \"$ref\").legacyPackages.$NIX_SYSTEM.${name} or null; in if p == null then \"\" else p.version or p.name" 2>/dev/null) || v=""
  printf '%s' "${v#"$name-"}"
}
