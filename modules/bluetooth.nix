{ pkgs, ... }:
let
  # The paging loop and its rationale live in scripts/bluetooth-reconnect.sh;
  # substituteAll only swaps in the bluez path.
  reconnectScript = pkgs.substituteAll {
    src = ../scripts/bluetooth-reconnect.sh;
    bluetoothctl = "${pkgs.bluez}/bin/bluetoothctl";
  };
in
{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # BlueZ does not page paired devices at adapter start; they only come back
  # if they connect themselves. Page every paired device until all are
  # connected, then exit. Devices appear a beat after bluetooth.target fires
  # and power-on is asynchronous, hence the retry loop.
  # Type=simple: nixos activation *waits* for oneshot start jobs, which would
  # block `nyx` for the whole loop; simple reports started on spawn and the
  # loop converges in the background instead. Stop (e.g. next rebuild) kills
  # the cgroup, so stale loops never pile up.
  # NB: pages *all* paired devices, in-ear headphones included — they will
  # auto-connect at boot when in range and PipeWire may switch output to them.
  systemd.services.bluetooth-reconnect = {
    description = "Connect paired Bluetooth devices after adapter start";
    after = [ "bluetooth.target" ];
    wantedBy = [ "bluetooth.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash ${reconnectScript}";
    };
  };
}
