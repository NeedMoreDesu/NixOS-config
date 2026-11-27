# AOC AGON AG326UD monitor control

**Status: reverse-engineered 2026-11-27 from AOC G-Menu 3.31.0. No Linux
app exists; the vendor commands can be sent directly over DDC/CI.**

## The important part

Start a Pixel Refresh by writing this DDC/CI packet to the monitor's DDC bus
(I2C 7-bit address `0x37`):

```text
51 86 03 E2 A0 36 00 01 CF
```

On this machine the AG326UD is on `HDMI-A-1`, whose DDC bus is `i2c-9`:

```bash
sudo i2ctransfer -y 9 w9@0x37 \
  0x51 0x86 0x03 0xe2 0xa0 0x36 0x00 0x01 0xcf
sleep 0.1
```

Packet breakdown:

```text
51        DDC/CI source address
86        0x80 | 6 data bytes
03        DDC/CI Set VCP Feature
E2        VCP code (vendor "external" command)
A0 36     TPV external command: 0xE2A0 family, opcode 0x36 = Pixel Refresh
00 01     value 1 = On
CF        checksum = 0x6E ^ 0x51 ^ 0x86 ^ 0x03 ^ 0xE2 ^ 0xA0 ^ 0x36 ^ 0x00 ^ 0x01
```

The checksum seed is the DDC/CI destination address `0x6E`. The app sleeps
100 ms after sending. The monitor then blinks its power LED and runs the
refresh for a few minutes; do not cut power during it.

Weirdly, `ddcutil setvcp 0xE2 0xA036` is **not** equivalent: standard
`setvcp` sends only the normal 4-byte payload (`03 E2 A0 36`) and omits the
`00 01` trigger value. This monitor accepts a 6-byte extended Set VCP. Use raw
I2C (`i2ctransfer`, or a small I2C_RDWR program), not `ddcutil setvcp`.

Related commands using the same framing:

| Action | Packet |
| --- | --- |
| Pixel Refresh On | `51 86 03 E2 A0 36 00 01 CF` |
| Pixel Refresh Off | `51 86 03 E2 A0 36 00 00 CE` |
| Auto Pixel Refresh On | `51 86 03 E2 A0 61 00 01 98` |
| Auto Pixel Refresh Off | `51 86 03 E2 A0 61 00 00 99` |

## Monitor and DDC bus

Identified from the HDMI EDID:

- Manufacturer `AOC` (EDID `0x05E3`), product `0xA611`, model string
  **`AG326UD`**, serial `10PRCJA000284`.
- Native mode 3840x2160; connected on `card1-HDMI-A-1`.
- DDC bus symlink:
  `/sys/class/drm/card1-HDMI-A-1/ddc -> ../../../i2c-9`.

Note: sysfs reports the EDID as size 0 but it is readable. `od`, `edid-decode`,
or `hdmi` tools can read it.

The app's own monitor DB entry for `AG326UD` is
`{"SupUsbDDC": false, "SupOTA": true, "UIType": 0}`, i.e. this model uses DDC/CI
over the video cable, not USB-HID DDC.

## Vendor app

Official download (G-Menu 3.31.0):

```text
https://aoc.com/api/asset/pi44150?ext=exe
```

This redirects to `satempmmdweprod.blob.core.windows.net/drivers/g-menu.exe`.
Downloaded 2026-11-27:

```text
size    136058200 bytes
sha256  f1239d2fea167aec8035fc7557e966a0d1b5a49afdf3d20feaf1fbfcc77aaafe
```

It is an NSIS 3.04 installer. The actual app is `$PLUGINSDIR/app-64.7z` inside
the installer. `app-64` contains:

- `G-Menu.exe` — Electron UI.
- `resources/app.asar` — Vue frontend; source maps recover the original
  `.vue`/JS source.
- `resources/bin/G_Menu.exe` — .NET backend, launched as a child process and
  spoken to over a local port (10020).
- `resources/bin/Zeasn.*.dll` — monitor/DDC support libraries.
- `resources/bin/DDCHelperLib.dll` — native 32-bit DDC/CI transport.

The separate OLED care guide is `pi53539` (`AGONBYAOC OLED CARE GUIDE 2026`).

## Protocol: TPV external DDC command

The command family is called `E2A0` in the app. Internally:

- `DDCHelperAttrOper`'s static constructor sets
  `E2A0 = (0xE2, 0xA0)` (a `ValueTuple<byte,byte>`).
- The enum `Zeasn.Equipment.Entity.Lib.E2A0_ExternVCPOpCode_E` encodes the
  opcode in the low byte of a 32-bit value, e.g.
  `EXT_OP_E2A0_36_PixelRefresh = 0x00E2A036`.
- `GetExtCode()` returns `enumValue & 0xFF`, e.g. `0x36`.
- The .NET side calls `SetTPVExternValue(appCommand=0xE2, code=0xA0,
  extCode=0x36, value)`.

`E2A0_ExternVCPOpCode_E` members found in G-Menu 3.31.0:

| Low byte | Enum member |
| --- | --- |
| `0x06` | `EXT_OP_E2A0_06_SharpShooter_Size` |
| `0x12` | `EXT_OP_E2A0_12_USB_C` |
| `0x13` | `EXT_OP_E2A0_13_USB_StandbyMode` |
| `0x18` | `EXT_OP_E2A0_18_LocalDimming` |
| `0x20` | `EXT_OP_E2A0_20_ColorGamut` |
| `0x21` | `EXT_OP_E2A0_21_DaisyChain` |
| `0x34` | `EXT_OP_E2A0_34_PixelOrbiting` |
| `0x35` | `EXT_OP_E2A0_35_ScreenSaver` |
| `0x36` | `EXT_OP_E2A0_36_PixelRefresh` |
| `0x40` | `EXT_OP_E2A0_40_AdaptiveSync` |
| `0x43` | `EXT_OP_E2A0_43_AutoWarning` |
| `0x45` | `EXT_OP_E2A0_45_ShadowBoost` |
| `0x46` | `EXT_OP_E2A0_46_LEA` (image-retention removal) |
| `0x4C` | `EXT_OP_E2A0_4C_MultiLogoProtection` |
| `0x4D` | `EXT_OP_E2A0_4D_BoundaryDimmer` |
| `0x4E` | `EXT_OP_E2A0_4E_TaskbarDimmer` |
| `0x4F` | `EXT_OP_E2A0_4F_ThermalProtection` |
| `0x61` | `EXT_OP_E2A0_61_AutoPixelRefresh` |

Full enum value is `0xE2A000 | lowByte`.

The app also has an `F8E1` external family (`F8E1_ExternVCPOpCode_E`) and the
normal `StandardVCPOpCode_E` family; those use the same external DDC plumbing
with different prefixes. Only the `E2A0` family is needed here.

## Why the value is 1

The frontend sends, for the manual Pixel Refresh button:

```js
this.$req.SetE2A0_ExternOSD_Uncached(
  'EXT_OP_E2A0_36_PixelRefresh',
  this.EXT_OP_E2A0_36_PixelRefresh.on
)
```

`src/shared/filter.js` builds that `.on` from the monitor support data:

```js
support: item.IsSupport,
on: item.IsSupport
  ? item.SupportChild.find((o) => o.Name.toLowerCase() === 'on')?.value
  : -1,
off: ...
```

The .NET `SupportOper` path maps each E2A0 opcode to an enum that describes its
children. For `0x36` (`PixelRefresh`) it uses `SwitchFlag_E`:

```text
SwitchFlag_E.Off = 0
SwitchFlag_E.On  = 1
```

So the actual Pixel Refresh command value is `1`. Auto Pixel Refresh (`0x61`)
uses the same `SwitchFlag_E` values, hence `1` to enable and `0` to disable.

## Full code path

Frontend:

- `src/views/device/monitor/OledPanelCare.vue` — `doPixelRefresh()`.
- `src/shared/filter.js` — builds `support`, `on`, `off` from
  `SupportChild`.
- `src/store/modules/monitor.js` — stores the support objects.

.NET backend, from the `SetE2A0_ExternOSD_Uncached` SignalR hub method:

1. `G_Menu.Hubs.GMenuHub.SetE2A0_ExternOSD_Uncached` →
   `Zeasn.Framework.Core.Lib.DisPlayBase.SetE2A0_ExternOSD` →
   `IDisPlay.SetE2A0_ExternOSD` →
   `Zeasn.Equipment.Base.Lib.AOCOper.SetE2A0_ExternOSD(itemName, iValue)`.
2. `AOCOper.Mq6PJ10SaG(list, itemName, iValue)` finds the `AttributeInfo` for
   the enum name in `E2A0_ExternList`, creates/updates it, then calls
   `DDCHelperAttrOper.SetValue(AttributeInfo)`.
3. `DDCHelperAttrOper.SetValue(AttributeInfo)` detects the E2A0 family and calls
   `SetValue(E2A0_ExternVCPOpCode_E, int)`.
4. That overload calls
   `SetTPVExternValue(0xE2, 0xA0, GetExtCode(enum), value)`.
5. `DDCHelAPIOper.SetTPVExternValue` calls
   `Zeasn.DDC.Lib.New.NewDDCOper.SetTPVExternDDCCIValue(displayIndex, 0xE2,
   0xA0, 0x36, value)`.
6. `CSDDCHelperOper.setTPVExternDDCCIValue_CS` calls
   `YyrWHHtMTriWmtBO3F.dVQnML1sepYxPclLmQ.IyMuuykNGd(...)`.
7. `IyMuuykNGd` builds the 520-byte command buffer:

   ```text
   [0] = 0x03        Set VCP opcode
   [1] = 0xE2        app command
   [2] = 0xA0        code
   [3] = 0x36        extCode
   [4] = value >> 8
   [5] = value & 0xFF
   command length = 6
   ```

8. The native 32-bit `DDCHelperLib.dll!_setTPVExternDDCCIValue_C@4` (RVA
   `0x4DE0`, internal packet builder `0x10008750`) wraps the 6 bytes:

   ```text
   0x51, 0x80 | 6, <6 bytes>, XOR checksum seeded with 0x6E and 0x51
   ```

   It writes to I2C 7-bit address `0x37`, then sleeps 100 ms.

## Sending it from Linux

Requirements:

- `i2c-dev` loaded (`boot.kernelModules = [ "i2c-dev" ];` if missing).
- Read/write access to `/dev/i2c-N` (normally `i2c` group or a udev rule).
- `i2c-tools` for `i2ctransfer`.

Find the DDC bus (re-check after changing input/cable):

```bash
readlink -f /sys/class/drm/card1-HDMI-A-1/ddc   # .../i2c-9
ddcutil detect --verbose                        # if ddcutil is installed
```

Send Pixel Refresh:

```bash
sudo i2ctransfer -y 9 w9@0x37 \
  0x51 0x86 0x03 0xe2 0xa0 0x36 0x00 0x01 0xcf
```

Send Auto Pixel Refresh On:

```bash
sudo i2ctransfer -y 9 w9@0x37 \
  0x51 0x86 0x03 0xe2 0xa0 0x61 0x00 0x01 0x98
```

Use the same command with value `00 00` and the matching checksum to send Off
(`... 0x36 00 00 ce` for Pixel Refresh). Do not write to the wrong I2C bus;
verify the DDC symlink first.

## Reproducing the extraction

Installer extraction (works without Windows):

```bash
nix-shell -p p7zip --run '
  7z x -y -oinstaller g-menu.exe &&
  7z x -y -oapp installer/\$PLUGINSDIR/app-64.7z
'
```

ASAR extraction note: `resources/app.asar` has a 16-byte header. The JSON
header length is the uint32 at offset 4; the JSON starts at offset 16, but file
data starts at `8 + headerLength` (there is 2-byte padding before data, and the
JSON length is not the file-data offset). Using `16 + parsedJsonLength` shifts
every extracted file by two bytes.

.NET inspection used in this reverse engineering:

- `monodis --typedef/--fields/--constant/--method/--memberref` for metadata.
- `monodis --customattr` for attributes.
- `dnfile` + `dncil` in Python for method bodies and token resolution.
  (`monodis` full-assembly IL output crashes on this assembly; per-table dumps
  work.)
- `objdump -d -M intel` on the 32-bit native `DDCHelperLib.dll` to verify the
  DDC wire framing and checksum.

The `app.asar` Vue source map (`app.4d6e7b70.js.map`) contains the original
source; it is much easier to read than the minified bundle.

## App UI quirks (not needed for the command)

- The manual Pixel Refresh button is rendered with
  `v-if="!EXT_OP_E2A0_36_PixelRefresh.support"` even though `support` comes
  from the monitor's support info. The command itself is independent of that
  flag.
- The confirmation dialog says the refresh takes a few minutes and the power
  LED blinks until it finishes; do not unplug power.
- The app has separate "Auto Pixel Refresh" (`0x61`) and manual "Pixel
  Refresh" (`0x36`) paths. Manual refresh is a one-shot trigger; auto refresh
  is an On/Off setting.
