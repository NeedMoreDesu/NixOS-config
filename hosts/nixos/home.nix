{ lib, plasma-manager, ... }:
{
  imports = [ plasma-manager.homeModules.plasma-manager ];

  home.username = "mika";
  home.homeDirectory = "/home/mika";
  home.stateVersion = "26.05";

  programs.plasma = {
    enable = true;

    # Direct keyboard-layout selection (KWin's global shortcut actions, named
    # after the xkb layout descriptions: extraLayouts.description / evdev.xml).
    # Meta+Alt+N is free; Super rides the physical Ctrl key (xremap
    # Control_L->Super_L), so this is the Mac "Option+Cmd+N" muscle-memory
    # version. Alt+Space cycles (xkb option), and
    # Meta+Alt+K / Meta+Alt+L (next / last-used) are KWin defaults.
    shortcuts = {
      "KDE Keyboard Layout Switcher" = {
        "Switch keyboard layout to English (UK, Macintosh) with grave" = "Meta+Alt+1";
        "Switch keyboard layout to Ukrainian" = "Meta+Alt+2";
      };
    };

    configFile = {
      "kwinrc"."Xwayland"."Scale" = 2.0;
      # Klipper clipboard auto-mirror was tested and rejected (2026-11-07,
      # see the pasteboard branch's DESIGN.md §12); pinned false so
      # re-enabling it via the KCM doesn't silently become policy.
      "klipperrc"."General"."SyncClipboards" = false;
    };

    # Mirrors ~/.config/plasma-org.kde.plasma.desktop-appletsrc:
    # left-edge panel with stock widget order.
    panels = [
      {
        location = "left";
        floating = true;
        opacity = "translucent";
        # plasma-manager has no option for this one yet; stored as
        # floatingApplets in the containment's [General] group.
        extraSettings = "panel.floatingApplets = true;";
        widgets = [
          {
            kickoff = { };
          }
          {
            iconTasks = { };
          }
          "org.kde.plasma.marginsseparator"
          # Keyboard layout indicator: standalone widget, NOT a tray item —
          # plasma-manager cannot configure widgets nested in the tray
          # (items.configs is upstream dead code, nix-community/plasma-manager#504),
          # and as its own widget it can pin displayStyle=flag (country-flag
          # emoji, rendered via KCountryFlagEmojiIconEngine + Noto Color Emoji).
          {
            keyboardLayout.displayStyle = "flag";
          }
          {
            systemTray = {
              items.shown = [ ];
            };
          }
          {
            digitalClock = { };
          }
          "org.kde.plasma.showdesktop"
          {
            pager = {
              general.displayedText = "desktopNumber";
            };
          }
        ];
      }
    ];
  };

  # Emacs config is a git repo of its own: the Prelude fork on GitHub
  # (upstream bbatsov/prelude kept as a remote for pulling updates).
  # Clone on first activation so a fresh machine is usable right after
  # `nyx`; never touch it afterwards — it is the user's working tree,
  # pulls/commits stay manual. Non-fatal on failure (network/ssh key)
  # so a rebuild never dies on it.
  home.activation.emacs-d = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.emacs.d/.git" ]; then
      $VERBOSE_ECHO "Cloning prelude fork into ~/.emacs.d"
      if git clone git@github.com:NeedMoreDesu/prelude.git "$HOME/.emacs.d"; then
        git -C "$HOME/.emacs.d" remote add upstream git@github.com:bbatsov/prelude.git
      else
        echo "WARNING: ~/.emacs.d clone failed (needs network + GitHub ssh key) - clone it manually" >&2
      fi
    fi
  '';

  # KScreen owns per-output scaling (plasma-manager has no kscreen module),
  # so re-assert our scale on every login.
  systemd.user.services.kscreen-scale = {
    Unit = {
      Description = "Force 200% scale on HDMI-A-1";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/kscreen-doctor output.HDMI-A-1.scale.2";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
