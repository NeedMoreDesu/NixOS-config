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
        [main]
        # Option-key role swap (2026-11-09): XKB (gb(mac) AND ua) hard-wire
        # level3(ralt_switch) — the RALT *keycode* is the alt-characters
        # layer, LALT is the plain Alt modifier. Swapping the keycodes here,
        # upstream of XKB, is the only clean place: keyd's maccycle and every
        # xremap combo EMIT the LALT keycode (A-tab, Alt-F4, Alt-grave...),
        # and those outputs bypass keyd (vendor 0x0fac skip) straight to XKB —
        # a downstream lv3: option swap would break all of them plus
        # grp:alt_space_toggle. Result: left option types alt-chars,
        # right option is the real Alt (Alt+Tab, Alt+Space layout switch,
        # menus). keyd does NOT canonicalize alt (proven: RALT survives
        # today as level3 trigger), so per-side rebinds work.
        # Syntax trap: direct assignment (`leftalt = rightalt`) PARSES but
        # keyd check exits 255 with "use layer(altgr)" warnings — the
        # descriptor form below is the sanctioned one (check exit 0).
        leftalt = layer(altgr)
        rightalt = layer(alt)

        # keyd normalizes BOTH cmd keys through the meta descriptor
        # (src/keys.c: MOD_SUPER -> canonical KEYD_LEFTMETA), so
        # KEY_RIGHTMETA never reaches xremap and Super_R rules are dead
        # code. Rebind right cmd to the plain Menu key: it is the only
        # output that keeps right cmd distinguishable downstream.
        # xremap turns Menu into CapsLock (emacs block -> Hyper via the
        # caps:hyper xkb option) or F13 (base block -> behaves like cmd
        # everywhere else). COST: right cmd no longer triggers the [meta]
        # layer, so the Cmd+Tab/grave swapm hold-cycle works on LEFT cmd
        # only. NOTE: bindings live in [main] — [global] is the
        # config-options section; rightmeta=menu there parses as a bogus
        # option, warns, and does nothing (keyd check shows it).
        rightmeta = menu

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
