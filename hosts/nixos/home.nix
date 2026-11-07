{ plasma-manager, ... }:
{
  imports = [ plasma-manager.homeModules.plasma-manager ];

  home.username = "mika";
  home.homeDirectory = "/home/mika";
  home.stateVersion = "26.05";

  programs.plasma = {
    enable = true;

    # Direct keyboard-layout selection (KWin's global shortcut actions, named
    # after the xkb layout descriptions: extraLayouts.description / evdev.xml).
    # Meta+Alt+N is free; Cmd is the real Meta (keyd), so this is the Mac
    # "Option+Cmd+N" muscle-memory version. Alt+Space cycles (xkb option), and
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
          {
            systemTray = {
              items.shown = [ "org.kde.plasma.keyboardlayout" ];
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
