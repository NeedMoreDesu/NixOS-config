{
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  # pasta (the box sandbox's egress-only network namespace) needs a tap.
  # udev already ships the /dev/net/tun 0666 rule, so loading the module is
  # enough; this also matters at boot, not only after a manual modprobe.
  boot.kernelModules = [ "tun" ];
}
