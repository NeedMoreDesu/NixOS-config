{ pkgs, seance, ... }:
let
  # pkgs.system is deprecated (warns "renamed to stdenv.hostPlatform.system");
  # flake outputs are still keyed by the plain system string.
  hostSystem = pkgs.stdenv.hostPlatform.system;

  # agent-browser's dedicated CDP Chromium (see scripts/agent-chrome.sh) and
  # its lazy front door (scripts/agent-browser.sh). substituteAll swaps the
  # store paths into the plain shell files.
  agentChromeScript = pkgs.substituteAll {
    src = ../scripts/agent-chrome.sh;
    browser = "${pkgs.agent-browser}/bin/agent-browser";
    chromium = "${pkgs.chromium}/bin/chromium";
    setsid = "${pkgs.util-linux}/bin/setsid";
  };
  agentBrowserScript = pkgs.substituteAll {
    src = ../scripts/agent-browser.sh;
    browser = "${pkgs.agent-browser}/bin/agent-browser";
    agent_chrome = "${agentChrome}/bin/agent-chrome";
  };
  agentChrome = pkgs.writeShellScriptBin "agent-chrome" ''
    exec ${pkgs.bash}/bin/bash ${agentChromeScript} "$@"
  '';
  agentBrowser = pkgs.writeShellScriptBin "agent-browser" ''
    exec ${pkgs.bash}/bin/bash ${agentBrowserScript} "$@"
  '';
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
    fastfetch
    sourcegit
    godot
    krita
    librewolf
    # Chromium is the CDP target for agent-browser (not a daily browser).
    chromium
    agentBrowser
    agentChrome
    # Namespace sandboxes for agent sessions (`box`, defined in
    # hosts/nixos/bashrc.sh): project mode mounts only runtime dirs + $PWD +
    # a random /tmp; -s/--system mounts / read-only plus a home allowlist.
    # bwrap is unprivileged, so no setuid helper.
    bubblewrap
    # pasta supplies the egress-only network namespace for `box` (host
    # loopback unreachable). `box -n/--network` opts back into the host netns
    # for agent-browser/CDP work. Needs the tun module (see networking.nix).
    passt
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
  ];
}
