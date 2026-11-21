# Bluetooth boot paging (removed)

The `bluetooth-reconnect` service and `scripts/bluetooth-reconnect.sh` were
removed on 2026-11-21.

## What it did

At boot, after `bluetooth.target`, it paged every **paired** device until all
showed `Connected: yes`:

- one background `bluetoothctl connect` job per device (BlueZ queues the
  pages itself); a serial connect would stall the whole loop behind the first
  unresponsive device;
- max 8 attempts per device, so a powered-off device would not drag the loop
  forever;
- `Type=simple` — NixOS activation waits for oneshot start jobs, which used
  to block `nyx` for minutes. `simple` reports started on spawn and converged
  in the background.

Caveat at the time: it paged *all* paired devices, in-ear headphones
included.

## Why it was removed

It made no observable difference. The peripherals ignore
`bluetoothctl connect` while idle/asleep (battery preservation); they only
reconnect once there is actual user activity to wake them. Scripted paging
was therefore wasted work.

`modules/bluetooth.nix` now only has:

```nix
hardware.bluetooth.enable = true;
hardware.bluetooth.powerOnBoot = true;
```

## What remained

Nothing depends on the old service. The physical devices themselves were
always fine: they accept paging once awake.
