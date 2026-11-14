# Packages frozen against the `nixpkgs-held` flake input instead of
# moving with nixpkgs. One nixpkgs attribute name per line. This list
# is imported by modules/held-packages.nix (the overlay) and read by
# scripts/flake-update.sh + scripts/flake-rollback.sh.
#
# Add/remove via scripts/flake-rollback.sh --hold/--release (re-pins
# nixpkgs-held to the last known-good nixpkgs rev and edits this file).
# Safe here ONLY for standalone binaries (zmx-style): the held
# derivation drags its old-tree dependencies into the closure beside
# the new ones. NOT for shared libraries (ABI), interpreter ecosystems,
# or packages with NixOS/home-manager modules — those belong in the
# HOLD_INPUTS list in flake-update.sh or an upstream fix.
[
  # zmx 1.0.1 SIGABRTs on every daemon shutdown, i.e. every `zmx kill`
  # = every seance cleanup shortcut: Daemon.run -> Daemon.deinit frees
  # a caller-owned socket_path with its post-fork C allocator. 0.8.1
  # (nixpkgs at f4a03c0, the nixpkgs-held pin) is clean. Upstream fix
  # is zmx main f5d604e (PR #316), not released/packaged yet. Release:
  #   scripts/flake-rollback.sh --release zmx
  # once `nyx -u` shows the hold and nixpkgs on the same fixed version.
  "zmx",
]
