#!/usr/bin/env bash
# AOC AGON AG326UD Pixel Refresh over DDC/CI.
#
# Reverse-engineered from AOC G-Menu 3.31.0. See docs/aoc_agon_monitor.md.
# Standalone: detects the AG326UD's DDC bus, loads i2c-dev if needed, and
# sends the vendor packet with an embedded Python I2C_RDWR call (no i2c-tools
# dependency). Run as a user; it re-executes itself via sudo for the I2C write.
set -euo pipefail

PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH
export PATH

self=$(readlink -f "$0")
orig_args=("$@")

usage() {
  cat <<'EOF'
usage: agon [options] [pixel|auto] [on|off]

  agon                  Pixel Refresh On
  agon off              Pixel Refresh Off
  agon auto on          Auto Pixel Refresh On
  agon auto off         Auto Pixel Refresh Off

options:
  -b, --bus N           DDC bus number (default: autodetect AG326UD)
  -n, --dry-run         print the packet and exit without sending
  -h, --help            this help
EOF
}

bus=${AGON_BUS:-}
mode=pixel
value=1
dry_run=0

while [ $# -gt 0 ]; do
  case $1 in
    -b|--bus)
      [ $# -ge 2 ] || { echo "agon: $1 needs an argument" >&2; exit 2; }
      bus=$2
      shift 2
      ;;
    -n|--dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    pixel|self) mode=pixel; shift ;;
    auto) mode=auto; shift ;;
    on) value=1; shift ;;
    off) value=0; shift ;;
    *) echo "agon: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

bus=${bus#i2c-}
if [ -n "$bus" ] && ! [[ $bus =~ ^[0-9]+$ ]]; then
  echo "agon: invalid bus: $bus" >&2
  exit 2
fi

find_bus() {
  local edid conn ddc
  for edid in /sys/class/drm/card*-*/edid; do
    conn=${edid%/edid}
    [ "$(cat "$conn/status" 2>/dev/null)" = connected ] || continue
    grep -aq 'AG326UD' "$edid" 2>/dev/null || continue
    ddc=$(readlink -f "$conn/ddc" 2>/dev/null) || continue
    case $ddc in
      *i2c-*) echo "${ddc##*i2c-}"; return 0 ;;
    esac
  done
  return 1
}

if [ -z "$bus" ]; then
  if ! bus=$(find_bus); then
    echo "agon: no connected AOC AG326UD found." >&2
    echo "      connected connectors:" >&2
    for edid in /sys/class/drm/card*-*/edid; do
      conn=${edid%/edid}
      [ "$(cat "$conn/status" 2>/dev/null)" = connected ] || continue
      ddc=$(readlink -f "$conn/ddc" 2>/dev/null) || ddc='?'
      echo "        ${conn##*/}  ddc=${ddc##*/}" >&2
    done
    echo "      pass --bus N (or AGON_BUS=N) if the bus is not detected." >&2
    exit 1
  fi
fi

op=0x36
[ "$mode" = auto ] && op=0x61

data=(0x03 0xE2 0xA0 "$op" $(((value >> 8) & 0xFF)) $((value & 0xFF)))
len=$((0x80 | ${#data[@]}))
csum=$((0x6E ^ 0x51 ^ len))
for b in "${data[@]}"; do
  csum=$((csum ^ b))
done
packet=(0x51 "$len" "${data[@]}" "$csum")

hex_packet() {
  local b out=''
  for b in "${packet[@]}"; do
    printf -v b '0x%02X' "$b"
    out+="${out:+ }$b"
  done
  printf '%s\n' "$out"
}

label='pixel refresh'
[ "$mode" = auto ] && label='auto pixel refresh'
state=off
if [ "$value" -eq 1 ]; then state=on; fi

if [ "$dry_run" -eq 1 ]; then
  echo "agon: ${label} ${state} (i2c-${bus})" >&2
  echo "agon: packet $(hex_packet)" >&2
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$self" --bus "$bus" "${orig_args[@]}"
fi

echo "agon: ${label} ${state} (i2c-${bus})" >&2
echo "agon: packet $(hex_packet)" >&2

if [ ! -e "/dev/i2c-${bus}" ]; then
  if ! modprobe i2c-dev 2>/dev/null; then
    echo "agon: /dev/i2c-${bus} missing and modprobe i2c-dev failed." >&2
    echo "      add boot.kernelModules = [ \"i2c-dev\" ]; and rebuild." >&2
    exit 1
  fi
  # Give udev a moment to create the node.
  for _ in 1 2 3 4 5; do
    [ -e "/dev/i2c-${bus}" ] && break
    sleep 0.1
  done
fi

if [ ! -e "/dev/i2c-${bus}" ]; then
  echo "agon: /dev/i2c-${bus} still missing after loading i2c-dev." >&2
  exit 1
fi

python3 - "$bus" "${packet[@]}" <<'PY'
import ctypes
import os
import sys
import time

I2C_RDWR = 0x0707
DDC_ADDR = 0x37

class I2CMsg(ctypes.Structure):
    _fields_ = [
        ("addr", ctypes.c_uint16),
        ("flags", ctypes.c_uint16),
        ("len", ctypes.c_uint16),
        ("buf", ctypes.POINTER(ctypes.c_uint8)),
    ]

class I2CRdwrData(ctypes.Structure):
    _fields_ = [
        ("msgs", ctypes.POINTER(I2CMsg)),
        ("nmsgs", ctypes.c_uint32),
    ]

bus = int(sys.argv[1])
payload = bytes(int(x, 0) for x in sys.argv[2:])

libc = ctypes.CDLL(None, use_errno=True)
libc.ioctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_void_p]
libc.ioctl.restype = ctypes.c_int

fd = os.open(f"/dev/i2c-{bus}", os.O_RDWR)
try:
    buf = (ctypes.c_uint8 * len(payload))(*payload)
    msg = I2CMsg(DDC_ADDR, 0, len(payload), buf)
    rdwr = I2CRdwrData(ctypes.pointer(msg), 1)
    if libc.ioctl(fd, I2C_RDWR, ctypes.byref(rdwr)) < 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
finally:
    os.close(fd)

time.sleep(0.1)
PY

echo "agon: sent." >&2
