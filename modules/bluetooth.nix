{ pkgs, ... }:
{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # BlueZ does not page paired BR/EDR HID keyboards at boot; do it ourselves
  # so the Magic Keyboard is connected before the first keystroke.
  systemd.services.magic-kbd-connect = {
    description = "Reconnect Magic Keyboard after adapter start";
    after = [ "bluetooth.target" ];
    wantedBy = [ "bluetooth.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bluez}/bin/bluetoothctl --timeout 20 connect 1C:F6:4C:00:B9:4E";
    };
  };
}
