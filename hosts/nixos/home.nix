{ plasma-manager, ... }:
{
  imports = [ plasma-manager.homeModules.plasma-manager ];

  home.username = "mika";
  home.homeDirectory = "/home/mika";
  home.stateVersion = "26.05";

  programs.plasma = {
    enable = true;

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
            pager = {
              general.displayedText = "desktopNumber";
            };
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
