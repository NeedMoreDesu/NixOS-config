{
  # The Cmd-key policy moved to modules/xremap.yml (xremap runs as a user
  # service, below XKB, with app-specific rules). keyd is gone: evdev grab is
  # exclusive per device, so keyd + xremap cannot sit on the same keyboard.
  # What remains here is the one thing neither xremap nor XKB owns:
  # the firmware-level function-row mode.

  # Top row = real F keys by default; brightness/volume/mission-control move
  # behind Fn (hid_apple.fnmode: 1 = fkeyslast [macOS behaviour], 2 =
  # fkeysfirst). Applies when the module loads, i.e. every boot.
  boot.kernelParams = [ "hid_apple.fnmode=2" ];
}
