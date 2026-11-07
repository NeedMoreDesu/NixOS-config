{ plasma-manager, ... }:
{
  imports = [ plasma-manager.homeModules.plasma-manager ];

  home.username = "mika";
  home.homeDirectory = "/home/mika";
  home.stateVersion = "26.05";

  programs.plasma = {
    enable = true;
    configFile = {
      "kdeglobals"."KScreen"."ScaleFactor" = 2.0;
      "kwinrc"."Xwayland"."Scale" = 2.0;
    };
  };

  home.sessionVariables = {
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
  };
}
