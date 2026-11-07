{
  # macOS muscle memory: ⌘ acts as Ctrl for app shortcuts (Cmd+C/V/X/A/S/O/F/Z
  # work as copy/paste/cut/select-all/save/open/find/undo in any app, on
  # Wayland, X and the console alike — keyd remaps at the evdev layer).
  # Physical Ctrl keeps sending Ctrl, so terminal Ctrl+C/^R/^W are unaffected.
  # A "macmeta" layer stands in for the Cmd key: it behaves as Ctrl for
  # everything except the handful of combos overridden below.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        leftmeta = "layer(macmeta)";
        rightmeta = "layer(macmeta)";
      };
      # separate section, must come after [main] (settings attrset sorts
      # alphabetically, so it can't live in settings)
      # NOTE: the closing '' sits at the same indent as the body so that every
      # line loses its leading whitespace (keyd needs [sections] at col 0)
      extraConfig = ''
        # ":C" = apply the Ctrl modifier to every pass-through key
        [macmeta:C]
        # Cmd+Tab / Cmd+Shift+Tab: cycle applications (Alt+Tab in KDE)
        tab = A-tab
        # Cmd+Space: Spotlight-ish -> application dashboard (KDE's built-in
        # search). Alt+F1 is plasmashell's default "activate application
        # launcher"; the Meta binding is unreachable since keyd swallows Meta.
        space = A-f1
        # Cmd+`: next window of the focused app (KWin's in-app switcher)
        grave = A-grave
        '';
    };
  };
}
