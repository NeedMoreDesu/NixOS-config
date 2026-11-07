{
  # Cmd is a real Meta everywhere EXCEPT for the handful of explicit combos
  # below — no blanket Cmd->Ctrl remapping (removed deliberately: it hijacks
  # every unknown Cmd+key, rewrites terminal dialects, and Cmd+C lands as
  # literal keyboard-quit in Emacs). keyd's built-in meta layer
  # (leftmeta/rightmeta are already bound to it) carries the overrides, so
  # nothing needs to be remapped in [main].
  #   Cmd+Tab / Cmd+`  -> KWin switchers with Alt HELD while Cmd is down
  #                       (swapm into an :A hold-layer; see below)
  #   Cmd+Space        -> application dashboard
  # Everything else (Cmd+C, Cmd+V, Cmd+S, ...) is plain Super+key: inert in
  # most apps, and Ctrl+C/^R/^W in terminals keep working physically.

  # Top row = real F keys by default; brightness/volume/mission-control move
  # behind Fn (hid_apple.fnmode: 1 = fkeyslast [macOS behaviour], 2 =
  # fkeysfirst). Applies when the module loads, i.e. every boot.
  boot.kernelParams = [ "hid_apple.fnmode=2" ];

  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      # keyd defines [meta:M] implicitly and binds leftmeta/rightmeta to it;
      # bindings added to [meta] extend that built-in layer. No [main]
      # remaps needed — and no :C blanket.
      # NOTE: the closing '' sits at the same indent as the body so that every
      # line loses its leading whitespace (keyd needs [sections] at col 0)
      extraConfig = ''
        [meta]
        # Switcher keys must HOLD Alt while Cmd is depressed (that is how the
        # KWin popups decide to stay open), which a plain `A-tab` tap cannot
        # express: keyd's modifier only lives as long as the physical key.
        # swapm(maccycle, key) enters an Alt layer that lives for the duration
        # of the Cmd press itself and emits the first press into it, so
        # press 1 opens the switcher and subsequent presses cycle. While the
        # hold-layer is active other keys act as Alt-combos (like a real
        # Cmd->Alt map would).
        tab = swapm(maccycle, tab)
        grave = swapm(maccycle, grave)
        # Cmd+Space: Spotlight-ish -> application dashboard. Alt+F1 is
        # plasmashell's default launcher binding.
        space = A-f1

        # Alt hold-layer entered by swapm above; stays active while Cmd is
        # down, so Tab/` presses cycle the open switcher.
        [maccycle:A]
        tab = A-tab
        grave = A-grave
        '';
    };
  };
}
