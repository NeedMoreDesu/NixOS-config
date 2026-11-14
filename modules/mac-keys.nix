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
        # Option keys (2026-11-14): BOTH are plain Alt on their own. XKB
        # (gb(mac) AND ua) hard-wire level3(ralt_switch) — the RALT *keycode*
        # is the alt-characters layer, LALT is the plain Alt modifier. keyd
        # does NOT canonicalize alt (RALT survives), so layer rebinds work.
        # The alt-char map is now a double-key chord: left cmd (the [meta]
        # layer) swaps either option key to keyd's built-in altgr:G layer,
        # so Cmd+Option+<key> types the level3 char while Option alone stays
        # a real Alt (Alt+Tab, Alt+Space layout switch, menus). Right cmd
        # stays `menu` (see below) and does NOT enter [meta], so the chord
        # is left-cmd only.
        #
        # swap(altgr), NOT layer(altgr): [meta] normally holds the Super
        # modifier, which xremap turns into its F13 virtual modifier. A
        # plain layer(altgr) would leave Super/F13 held alongside RALT, and
        # xremap's inexact F13-<key> rules would win over the alt char
        # (F13-e -> Ctrl-e). swap() deactivates the meta layer for the
        # chord, shedding Super/F13 before RALT is emitted; keyd then sends
        # a clean RALT+<key> that XKB level3 resolves per layout. The swap
        # is banked on the cmd keypress: press Cmd BEFORE Option, and AltGr
        # remains engaged until Cmd is released (releasing Option first does
        # not swap back to meta).
        #
        # Syntax trap: direct assignment (`leftalt = rightalt`) PARSES but
        # keyd check exits 255 with "use layer(altgr)" warnings — the
        # descriptor form below is the sanctioned one (check exit 0).
        leftalt = layer(alt)
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
        # left cmd + either option = AltGr for the next keys (see above).
        leftalt = swap(altgr)
        rightalt = swap(altgr)

        [maccycle:A]
        tab = A-tab
        grave = A-grave
        '';
    };
  };
}
