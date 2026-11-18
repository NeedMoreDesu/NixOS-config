{
  description = "Mika's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Frozen nixpkgs serving the per-package holds in
    # scripts/held-packages.nix (modules/held-packages.nix overlays
    # them): nixpkgs itself updates freely again, a regressed package is
    # served from THIS rev instead. Never bumped by `nyx -u` (it is the
    # HOLD_INPUTS entry); it moves only via
    # scripts/flake-rollback.sh --hold (re-pin to the last known-good
    # nixpkgs). Currently f4a03c0 = the rev carrying zmx 0.8.1 (the
    # nixpkgs zmx 1.0.1 SIGABRT; see held-packages.nix).
    nixpkgs-held.url = "github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6";
    llm-agents.url = "github:numtide/llm-agents.nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # Scrolling GTK4/libadwaita terminal multiplexer that tracks AI coding
    # agents (MIT, Zig, Linux/Wayland). Built against OUR nixpkgs (shared
    # glib/GL/store closure — the right thing for a GUI app on NixOS), but
    # ghostty is a git submodule it compiles against, hence submodules = true.
    # FORK (github.com/NeedMoreDesu/seance, branch zmx): per-terminal UUIDs
    # persisted in session.json, [hooks] on-tab-open/close, [behavior]
    # zmx-attach (each pane exec's `zmx attach seance-<pane-uuid>`). Until
    # the fork is pushed, pinned to the local clone at ~/seance.
    seance = {
      url = "git+file:///home/mika/seance?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Key remapper for X11/Wayland with app-specific rules (evdev level —
    # sits BELOW XKB). No follows: its module ships its own pinned nixpkgs +
    # crane and builds the static xremap-kde binary against them; following
    # ours would only change the (Rust-only) build deps. Same policy as
    # llm-agents: don't follow, don't share closure for pure static binaries.
    xremap-flake.url = "github:xremap/nix-flake";
  };

    outputs =
      inputs@{
        nixpkgs,
        nixpkgs-held,
        llm-agents,
        home-manager,
        seance,
        xremap-flake,
        ...
      }:
    let
      # Explicit host registry: nothing auto-discovers hosts/<name>; each
      # nixosConfigurations key points at its own host directory.
      mkHost = name: nixpkgs.lib.nixosSystem {
        # no `system` arg: deprecated (warns as renamed to
        # stdenv.hostPlatform.system); the platform comes from
        # nixpkgs.hostPlatform in hardware-configuration.nix
        specialArgs = {
          inherit llm-agents home-manager seance nixpkgs-held;
          plasma-manager = inputs.plasma-manager;
          hostName = name;
        };
        modules = [
          ./hosts/${name}/default.nix
          home-manager.nixosModules.home-manager
          xremap-flake.nixosModules.default
        ];
      };
    in
    {
      nixosConfigurations = {
        nixos = mkHost "nixos";
        # qwerty = mkHost "qwerty";
      };
    };
}
