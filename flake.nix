{
  description = "Mika's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
    seance = {
      url = "git+https://github.com/no1msd/seance?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # tmux + git-worktree orchestrator for parallel AI coding agents (MIT,
    # Rust). Own flake with a `packages.default`; follows our nixpkgs.
    workmux = {
      url = "github:raine/workmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

    outputs =
      inputs@{
        nixpkgs,
        llm-agents,
        home-manager,
        seance,
        workmux,
        ...
      }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit llm-agents home-manager seance workmux;
          plasma-manager = inputs.plasma-manager;
        };
        modules = [
          ./hosts/nixos/default.nix
          home-manager.nixosModules.home-manager
        ];
      };
    };
}
