{
  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    enableHidpi = true;
  };
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    # gb/mac with the §/± key (left of 1) replaced by ` / ~. KWin matches the
    # in-app window switcher ("Walk Through Windows of Current Application") by
    # keysym, so keyd's Cmd+` -> Alt+grave only lands once this key's symbols
    # are actually grave/asciitilde instead of section/plusminus.
    layout = "gb-mac-grave";
    options = "caps:ctrl_modifier";

    extraLayouts.gb-mac-grave = {
      description = "English (UK, Macintosh) with grave instead of section";
      languages = [ "eng" ];
      symbolsFile = ./xkb-gb-mac-grave;
    };
  };
}
