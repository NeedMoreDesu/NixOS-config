{ pkgs, seance, ... }:
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
    # Seance comes from its own flake input (github:no1msd/seance), not
    # nixpkgs — built against our pkgs via the follows = "nixpkgs" redirect.
    seance.packages.${pkgs.system}.seance
  ];
}
