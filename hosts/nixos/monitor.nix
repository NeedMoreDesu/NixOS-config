{
  # AOC AGON AG326UD DDC/CI access for the `agon` Pixel Refresh helper.
  # See docs/aoc_agon_monitor.md.
  #
  # i2c-dev creates /dev/i2c-*; udev gives mika ownership so the xremap
  # Cmd+F12 shortcut can run the script without a sudo prompt.
  boot.kernelModules = [ "i2c-dev" ];

  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", OWNER="mika", MODE="0600"
  '';
}
