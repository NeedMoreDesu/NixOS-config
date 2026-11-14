{ pkgs, seance, ... }:
let
  # pkgs.system is deprecated (warns "renamed to stdenv.hostPlatform.system");
  # flake outputs are still keyed by the plain system string.
  hostSystem = pkgs.stdenv.hostPlatform.system;

  # CDP-enabled Chromium for agent-browser. Own profile dir + fixed port so
  # the debug endpoint never exposes the normal browser's tabs, and so
  # --auto-connect's 9222 probe finds it. Port stays on 127.0.0.1.
  agentChrome = pkgs.writeShellScriptBin "agent-chrome" ''
    set -eu

    port=9222
    profile="$HOME/.local/share/agent-chrome"

    if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      ${pkgs.util-linux}/bin/setsid -f ${pkgs.chromium}/bin/chromium \
        --user-data-dir="$profile" \
        --remote-debugging-port="$port" \
        --no-first-run \
        --no-default-browser-check \
        >/dev/null 2>&1
    fi

    i=0
    until (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
      i=$((i + 1))
      if [ "$i" -gt 100 ]; then
        echo "agent-chrome: Chromium never opened CDP port $port" >&2
        exit 1
      fi
      sleep 0.1
    done

    exec ${pkgs.agent-browser}/bin/agent-browser --auto-connect --pin-tab "$@"
  '';

  # Lazy front door: starts agent-chrome on the first browser command, then
  # hands off. Commands that never touch a page (skills/dashboard/install/
  # close/...) skip the launch; an explicit --cdp/--auto-connect/connect
  # means the caller manages the browser.
  agentBrowser = pkgs.writeShellScriptBin "agent-browser" ''
    set -eu

    real=${pkgs.agent-browser}/bin/agent-browser

    sub=""
    skip_value=0
    direct=0
    no_browser=0

    for a in "$@"; do
      if [ "$skip_value" -eq 1 ]; then
        skip_value=0
        continue
      fi
      case "$a" in
        --cdp|--cdp=*|--auto-connect|--no-auto-connect|connect)
          direct=1
          ;;
        --help|-h|--version|-V)
          no_browser=1
          ;;
        --session|--profile|--headers|--executable-path|--args|--user-agent|--proxy|--proxy-bypass|--name|-n|--color-scheme|--provider|-p|--cdp-headers)
          skip_value=1
          ;;
        -*)
          ;;
        *)
          [ -z "$sub" ] && sub="$a"
          ;;
      esac
    done

    if [ "$direct" -eq 1 ] || [ "$no_browser" -eq 1 ]; then
      exec "$real" "$@"
    fi

    case "$sub" in
      ""|skills|dashboard|install|upgrade|doctor|close|stream)
        exec "$real" "$@"
        ;;
    esac

    exec ${agentChrome}/bin/agent-chrome "$@"
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
