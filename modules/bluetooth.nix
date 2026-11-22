{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # The Realtek RTL8922AE combo exposes its Bluetooth half as a USB
  # device (13d3:3617) even though the antenna is external. Keep that
  # controller out of USB runtime autosuspend: it was already "active"
  # during the captured stalls, so this is an A/B test rather than a
  # confirmed fix for the Magic Keyboard link timeouts.
  boot.kernelParams = [ "btusb.enable_autosuspend=0" ];
}
