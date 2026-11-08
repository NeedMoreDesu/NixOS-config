{
  # keyd as a MINIMAL sidecar under xremap (chain: hardware -> keyd ->
  # xremap -> KWin). It exists for exactly one thing xremap cannot do:
  # keeping Alt physically HELD across repeated Tab/grave presses
  # (swapm into [maccycle:A], which lives as long as Cmd is down) — the
  # KWin switcher popups stay open only while a real modifier is held.
  # Everything else (caps/ctrl/cmd cycle, Cmd->app combos) is xremap's
  # job; Cmd+Space deliberately NOT here (xremap's F13-space does it).
  #
  # xremap reads ONLY keyd's virtual device (deviceNames in xremap.nix)
  # and emits its output with vendor 0x0fac so keyd's is_virtual check
  # skips it — otherwise keyd would grab xremap's output and the two
  # remappers would feed each other in a loop.
  #
  # Caveat inherited from keyd: while [maccycle:A] is active (after the
  # first Cmd+Tab/grave, until Cmd is released), other keys emit
  # Alt-combos. That's what made the switcher cycle; keep bindings sparse.

  # Top row = real F keys by default; brightness/volume/mission-control move
  # behind Fn (hid_apple.fnmode: 1 = fkeyslast [macOS behaviour], 2 =
  # fkeysfirst). Applies when the module loads, i.e. every boot.
  boot.kernelParams = [ "hid_apple.fnmode=2" ];

  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      # NOTE: the closing '' sits at the same indent as the body so that every
      # line loses its leading whitespace (keyd needs [sections] at col 0)
      extraConfig = ''
        [meta]
        tab = swapm(maccycle, tab)
        grave = swapm(maccycle, grave)

        [maccycle:A]
        tab = A-tab
        grave = A-grave
        '';
    };
  };
}
