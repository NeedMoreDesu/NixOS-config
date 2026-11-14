# Per-package holds: the nixpkgs input updates freely again, but every
# name in scripts/held-packages.nix is overlaid from the frozen
# nixpkgs-held input (a known-good nixpkgs rev). This replaced holding
# ALL of nixpkgs for the zmx 1.0.1 SIGABRT. `nyx -u` prints held vs
# current versions per name; scripts/flake-rollback.sh --hold/--release
# manages the list and the nixpkgs-held pin. Only safe for standalone
# binaries — the held derivation drags its own old-tree dependencies
# alongside the new ones (no shared-ABI libraries, no NixOS modules).
{
  lib,
  pkgs,
  nixpkgs-held,
  ...
}:
let
  # pkgs.system is deprecated (warns); flake outputs are still keyed by
  # the plain system string.
  hostSystem = pkgs.stdenv.hostPlatform.system;
  heldNames = import ../scripts/held-packages.nix;
  heldPkgs = nixpkgs-held.legacyPackages.${hostSystem};
in
{
  nixpkgs.overlays = lib.mkIf (heldNames != [ ]) [
    (
      final:
      prev:
      builtins.listToAttrs (
        map
          (
            name:
            {
              inherit name;
              value = heldPkgs.${name} or (builtins.throw ''
                scripts/held-packages.nix: '${name}' is not in the nixpkgs-held pin —
                drop the hold or re-pin it: scripts/flake-rollback.sh --hold ${name} [ref]
              '');
            }
          )
          heldNames
      )
    )
  ];
}
