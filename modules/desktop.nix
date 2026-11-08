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
    # keysym, so xremap's F13+grave -> Alt+grave only lands once this key's
    # symbols are actually grave/asciitilde instead of section/plusminus.
    # Secondary layout: the r2u "Ukrainian Unicode" layout ships upstream in
    # xkeyboard-config as ua(unicode) — it IS the r2u layout (third level via
    # RAlt: apostrophe, ², ₴, °, —, other Cyrillics...). Pinned explicitly so
    # an upstream default change couldn't silently swap us to winkeys.
    # Alt+Space cycles layouts (xkb-native, so it already works in SDDM).
    # caps:ctrl_modifier removed 2026-11-08: the whole caps/ctrl/cmd cycle now
    # lives in xremap's modmap (modules/xremap.yml); XKB only does layout
    # symbols here. Side effect: the SDDM greeter keyboard is now vanilla
    # (xremap is a session user service).
    layout = "gb-mac-grave,ua";
    variant = ",unicode";
    options = "grp:alt_space_toggle";

    extraLayouts.gb-mac-grave = {
      description = "English (UK, Macintosh) with grave instead of section";
      languages = [ "eng" ];
      symbolsFile = ./xkb-gb-mac-grave;
    };
  };
}
