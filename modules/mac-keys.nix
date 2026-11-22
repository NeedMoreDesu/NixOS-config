{ pkgs, ... }:
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

    # keyd 2.6.0 only logs EV_DEV_REMOVE; a key held when the Bluetooth
    # link times out never gets its key-up, so it stays down on keyd's
    # virtual device. The local patch implements kbd_reset() and calls it
    # plus clear_vkbd() on removal. See docs/keyboard.md and
    # patches/keyd-release-on-remove.patch; drop it when upstream does this.
    package = pkgs.keyd.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/keyd-release-on-remove.patch
      ];
    });

    keyboards.default = {
      ids = [ "*" ];
      # Policy lives in assets/mac-keys/keyd.conf (sections must be at col 0;
      # a regular file avoids the indented-string escaping trap).
      extraConfig = builtins.readFile ../assets/mac-keys/keyd.conf;
    };
  };
}
