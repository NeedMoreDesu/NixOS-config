{
  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    enableHidpi = true;
  };
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    # gb/mac with the §/± key (left of 1) replaced by ` / ~ — keyd fired its
    # grave remap on that key's keycode, and Toshy's Cmd+` -> Alt+grave chain
    # only reaches KWin once the keysym actually is grave.
    layout = "gb-mac-grave";
    options = "caps:ctrl_modifier";

    extraLayouts.gb-mac-grave = {
      description = "English (UK, Macintosh) with grave instead of section";
      languages = [ "eng" ];
      symbolsFile = ./xkb-gb-mac-grave;
    };
  };
}
