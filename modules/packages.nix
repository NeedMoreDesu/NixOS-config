{ pkgs, seance, workmux, ... }:
let
  # pkgs.system is deprecated (warns "renamed to stdenv.hostPlatform.system");
  # flake outputs are still keyed by the plain system string.
  hostSystem = pkgs.stdenv.hostPlatform.system;
in
{
  # Steam ships unfree deps; scoped by name prefix so nothing else silently
  # turns unfree on (matches steam, steam-run, steam-friends, steam-runtime...).
  nixpkgs.config.allowUnfreePredicate = pkg: pkgs.lib.hasPrefix "steam" (pkgs.lib.getName pkg);

  programs.firefox.enable = true;

  # Steam as a module (not just the package): sets up the FHS sandbox,
  # hardware.steam-hardware, 32-bit PipeWire/Pulse audio, Gamescope session.
  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    git
    sourcegit
    godot
    krita
    librewolf
    tmux
    # KDE Partition Manager: the two-partition layout (1G EFI + rest ext4)
    # lives here when you want to look at it graphically (nixpkgs-only, no
    # flake input; kdePackages subset of the Qt6 stack).
    kdePackages.partitionmanager
    # zmx: session attach/detach (tmux-lite, Zig). In nixpkgs — no flake
    # input — but while it sits in scripts/held-packages.nix its actual
    # version comes from the nixpkgs-held overlay (modules/held-packages.nix).
    zmx
    # Seance comes from its own flake input (github:no1msd/seance), not
    # nixpkgs — built against our pkgs via the follows = "nixpkgs" redirect.
    seance.packages.${hostSystem}.seance
    # workmux: parallel agents in tmux windows, one git worktree per task.
    # Flake output is packages.default (github:raine/workmux).
    workmux.packages.${hostSystem}.default
  ];
}
