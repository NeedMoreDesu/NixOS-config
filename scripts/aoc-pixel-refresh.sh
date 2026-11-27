#!/usr/bin/env bash
# AOC AGON AG326UD Pixel Refresh over DDC/CI.
#
# Reverse-engineered from AOC G-Menu 3.31.0. See docs/aoc_agon_monitor.md.
# No arguments: always triggers Pixel Refresh On on the detected AG326UD.
set -euo pipefail

# /run/wrappers/bin must come first: /run/current-system/sw/bin/sudo is not
# setuid on NixOS; the setuid wrapper lives in /run/wrappers/bin.
PATH=/run/wrappers/bin:/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH
export PATH

if [ $# -ne 0 ]; then
  echo "agon: takes no arguments" >&2
  exit 2
fi

self=$(readlink -f "$0")

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

if ! bus=$(find_bus); then
  echo "agon: no connected AOC AG326UD found." >&2
  echo "      connected connectors:" >&2
  for edid in /sys/class/drm/card*-*/edid; do
    conn=${edid%/edid}
    [ "$(cat "$conn/status" 2>/dev/null)" = connected ] || continue
    ddc=$(readlink -f "$conn/ddc" 2>/dev/null) || ddc='?'
    echo "        ${conn##*/}  ddc=${ddc##*/}" >&2
  done
  exit 1
fi

if [ "$(id -u)" -ne 0 ] &&
   { [ ! -e "/dev/i2c-${bus}" ] || [ ! -w "/dev/i2c-${bus}" ]; }; then
  exec sudo -- "$self"
fi

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

echo "agon: pixel refresh on (i2c-${bus})" >&2
echo "agon: packet 51 86 03 E2 A0 36 00 01 CF" >&2

python3 - "$bus" <<'PY'
import ctypes
import os
import sys
import time

I2C_RDWR = 0x0707
DDC_ADDR = 0x37
PACKET = bytes([0x51, 0x86, 0x03, 0xE2, 0xA0, 0x36, 0x00, 0x01, 0xCF])

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

libc = ctypes.CDLL(None, use_errno=True)
libc.ioctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_void_p]
libc.ioctl.restype = ctypes.c_int

fd = os.open(f"/dev/i2c-{bus}", os.O_RDWR)
try:
    buf = (ctypes.c_uint8 * len(PACKET))(*PACKET)
    msg = I2CMsg(DDC_ADDR, 0, len(PACKET), buf)
    rdwr = I2CRdwrData(ctypes.pointer(msg), 1)
    if libc.ioctl(fd, I2C_RDWR, ctypes.byref(rdwr)) < 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
finally:
    os.close(fd)

time.sleep(0.1)
PY

echo "agon: sent." >&2
