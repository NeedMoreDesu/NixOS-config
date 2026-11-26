{ pkgs, seance, ... }:
let
  # pkgs.system is deprecated (warns "renamed to stdenv.hostPlatform.system");
  # flake outputs are still keyed by the plain system string.
  hostSystem = pkgs.stdenv.hostPlatform.system;

  # agent-browser's dedicated CDP Chromium (see scripts/agent-chrome.sh) and
  # its lazy front door (scripts/agent-browser.sh). replaceVars swaps the
  # store paths into the plain shell files.
  agentChromeScript = pkgs.replaceVars ../scripts/agent-chrome.sh {
    browser = "${pkgs.agent-browser}/bin/agent-browser";
    chromium = "${pkgs.chromium}/bin/chromium";
    setsid = "${pkgs.util-linux}/bin/setsid";
  };
  agentBrowserScript = pkgs.replaceVars ../scripts/agent-browser.sh {
    browser = "${pkgs.agent-browser}/bin/agent-browser";
    agent_chrome = "${agentChrome}/bin/agent-chrome";
  };
  agentChrome = pkgs.writeShellScriptBin "agent-chrome" ''
    exec ${pkgs.bash}/bin/bash ${agentChromeScript} "$@"
  '';
  agentBrowser = pkgs.writeShellScriptBin "agent-browser" ''
    exec ${pkgs.bash}/bin/bash ${agentBrowserScript} "$@"
  '';
  # In-box TTY resize watcher. bwrap --new-session detaches the boxed
  # command from the PTY's foreground pgrp, so TUIs miss SIGWINCH; box.sh
  # wraps interactive commands with this helper.
  boxTtyWatch = pkgs.callPackage ../pkgs/box-tty-watch.nix { };
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
    # Python 3 with pip + the venv module, so `python -m venv` works out of
    # the box. Building C extensions from source in a venv also needs a
    # toolchain/headers (gcc, pkg-config, ...); prebuilt wheels don't.
    python3
    sourcegit
    godot
    krita
    keepassxc
    librewolf
    # Chromium is the CDP target for agent-browser (not a daily browser).
    chromium
    agentBrowser
    agentChrome
    # Namespace sandboxes for agent sessions (`box`, defined in
    # shell/box.sh): project mode mounts only runtime dirs + $PWD +
    # a random /tmp; -s/--system mounts / read-only plus a home allowlist.
    # bwrap is unprivileged, so no setuid helper.
    bubblewrap
    # In-box SIGWINCH watcher (shell/box.sh wraps interactive commands;
    # BOX_NO_TTY_WATCH=1 opts out). See docs/sandbox.md.
    boxTtyWatch
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
