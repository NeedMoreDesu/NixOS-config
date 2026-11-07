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
    };

    # Mirrors ~/.config/plasma-org.kde.plasma.desktop-appletsrc:
    # left-edge panel with stock widget order.
    panels = [
      {
        location = "left";
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
