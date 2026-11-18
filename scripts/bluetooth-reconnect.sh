#!/usr/bin/env bash
# Page every paired Bluetooth device until all are connected, then exit.
# Runs as the bluetooth-reconnect service (modules/bluetooth.nix).
#
# BlueZ does not page paired devices at adapter start; they only come back
# if they connect themselves. Devices appear a beat after bluetooth.target
# fires and power-on is asynchronous, hence the retry loop.
#
# Each device gets its own background connect job (BlueZ queues the pages
# itself); a dead job is re-issued on the next round, but only up to 8
# times — a powered-off device must not drag every round on forever.
# Serial connects would block the whole loop on the first unresponsive
# device.
#
# NB: pages *all* paired devices, in-ear headphones included — they will
# auto-connect at boot when in range and PipeWire may switch output to them.

bt=@bluetoothctl@
declare -A conn_pid tries
for i in $(seq 1 30); do
  devices=$($bt --timeout 5 devices Paired | awk '{print $2}')
  # adapter not registered yet: no device list at all
  [ -n "$devices" ] || { sleep 1; continue; }
  pending=0
  working=0
  for mac in $devices; do
    if ! $bt --timeout 5 info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
      pending=1
      pid=${conn_pid[$mac]:-}
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        # page still in flight
        working=1
      elif [ "${tries[$mac]:-0}" -lt 8 ]; then
        tries[$mac]=$(( ${tries[$mac]:-0} + 1 ))
        $bt --timeout 30 connect "$mac" >/dev/null 2>&1 &
        conn_pid[$mac]=$!
        working=1
      fi
    fi
  done
  [ "$pending" = 0 ] && exit 0
  # every straggler has run out of attempts
  [ "$working" = 0 ] && exit 0
  sleep 1
done
exit 0
