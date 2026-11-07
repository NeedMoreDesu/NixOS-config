{ pkgs, ... }:
{
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # BlueZ does not page paired devices at adapter start; they only come back
  # if they connect themselves. Page every paired device until all are
  # connected (or ~30 rounds). Devices appear a beat after bluetooth.target
  # fires and power-on is asynchronous, hence the retry loop.
  # Each device gets its own background connect job (BlueZ queues the pages
  # itself); a dead job is re-issued on the next round. Serial connects would
  # block the whole loop on the first unresponsive device.
  # NB: pages *all* paired devices, in-ear headphones included — they will
  # auto-connect at boot when in range and PipeWire may switch output to them.
  systemd.services.bluetooth-reconnect = {
    description = "Connect paired Bluetooth devices after adapter start";
    after = [ "bluetooth.target" ];
    wantedBy = [ "bluetooth.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "bluetooth-reconnect" ''
        bt=${pkgs.bluez}/bin/bluetoothctl
        declare -A conn_pid
        for i in $(seq 1 30); do
          devices=$($bt --timeout 5 devices Paired | awk '{print $2}')
          # adapter not registered yet: no device list at all
          [ -n "$devices" ] || { sleep 1; continue; }
          pending=0
          for mac in $devices; do
            if ! $bt --timeout 5 info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
              pending=1
              pid=''${conn_pid[$mac]:-}
              # not started yet, or previous attempt already died: page again
              if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
                $bt --timeout 30 connect "$mac" >/dev/null 2>&1 &
                conn_pid[$mac]=$!
              fi
            fi
          done
          [ "$pending" = 0 ] && exit 0
          sleep 1
        done
        exit 0
      '';
    };
  };
}
