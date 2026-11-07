{ pkgs, ... }:
{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # BlueZ does not page paired BR/EDR HID keyboards at boot; keep paging the
  # Magic Keyboard once the adapter is actually up (it appears a beat later
  # than bluetooth.target fires, and power-on is asynchronous).
  systemd.services.magic-kbd-connect = {
    description = "Reconnect Magic Keyboard after adapter start";
    after = [ "bluetooth.target" ];
    wantedBy = [ "bluetooth.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "magic-kbd-connect" ''
        for i in $(seq 1 30); do
          if ${pkgs.bluez}/bin/bluetoothctl --timeout 5 connect 1C:F6:4C:00:B9:4E 2>&1 | grep -q "Connection successful"; then
            exit 0
          fi
          sleep 1
        done
        exit 0
      '';
    };
  };
}
