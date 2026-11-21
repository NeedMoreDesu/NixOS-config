# Plasma desktop and session

Plasma 6 + SDDM (Wayland, HiDPI on) are enabled in `modules/desktop.nix`.
XKB layouts live there too; see [keyboard](keyboard.md) for the input stack
and the KWin shortcut policy.

`home/plasma.nix` declares the whole desktop through `programs.plasma`:
panel, top bar, dock pins, widgets and shortcuts. plasma-manager writes the
config and a desktop script (`xdg.dataFile plasma-manager/data/*.js`) which
is run at login autostart or by `nyx -k`; the switch's own activation cannot
touch the session bus (see [rebuild](rebuild.md)). GUI pin/drag changes are
lost on the next `nyx`.

## Left panel

- The `keyboardlayout` widget is **standalone**, with `displayStyle=flag`.
  Tray-nested widgets cannot be configured: plasma-manager's
  `items.configs` is dead code upstream (issue #504).
- The tray **duplicate** of `keyboardlayout` (2026-11-09): plasmashell's
  `PlasmoidRegistry` auto-nests every applet whose metadata has
  `EnabledByDefault` + `X-Plasma-NotificationAreaCategory`
  (`keyboardlayout` = Hardware), regardless of panel declarations. GUI
  removal never sticks. Exclusion is declared via `systemTray.items.extra`
  — the `extraItems` list, now a 17-item allowlist **without**
  `keyboardlayout`; `knownItems` still lists it, which keeps the registry
  from re-adding it at login.
- Dock pins (`iconTasks` `launchers`) are declared in the panel:
  `seance → librewolf → sourcegit`. Pin real `.desktop` names —
  `preferred://browser` failed.
- The task list is global: `showTasks.onlyInCurrentDesktop = false` and
  `onlyInCurrentActivity = false`, so running apps stay in the dock on every
  virtual desktop/activity.

## Top bar

A thin (30px) panel at the top (2026-11-14):

- **One** `org.kde.plasma.systemmonitor` widget shows related stats as
  grouped rows (2026-11-21):

  | Row | Sensors | Example |
  | --- | --- | --- |
  | CPU | `cpu/all/usage` + `cpu/all/maximumTemperature` | `CPU 12% 55 °C` |
  | GPU | `gpu/gpu0/usage` + `gpu/gpu0/usedVram` + `gpu/gpu0/totalVram` + `gpu/gpu0/temperature` | `GPU 7% 3.2 / 15.9 GiB 41 °C` |
  | RAM | `memory/physical/used` + `memory/physical/total` | `RAM 8.7 / 30.5 GiB` |
  | ↓/↑ | `network/all/download` + `network/all/upload` | `↓ 1.2 MiB/s ↑ 0.3 MiB/s` |
  | R/W | `disk/all/read` + `disk/all/write` | `R 4.0 MiB/s W 2.0 MiB/s` |
  | DSK | `disk/all/usedPercent` (root disk space used, **not** load) | `DSK 46%` |

  On this host `gpu0` is the discrete Navi 48 (RX 9070) and `gpu1` is the
  Granite Ridge iGPU; the GPU row deliberately uses `gpu0` so usage, VRAM
  and temperature all refer to the same device. Used/total pairs are the
  preferred RAM/VRAM format; the face shows the single value if a total is
  unavailable. Verify sensor IDs live:
  `qdbus --literal org.kde.ksystemstats1 /org/kde/ksystemstats1 allSensors`.

- Then `org.kde.plasma.marginsseparator` (2026-11-21), then the
  `org.kde.mika.btbattery` applet: connected Bluetooth charge per
  device as type+value, e.g. `Battery: K 100% M 100% H 90%`. It asks
  `contents/tools/bt-battery.sh` for `TYPE<TAB>PCT<TAB>NAME` lines and
  intersects `bluetoothctl devices Connected` with UPower
  (`serial`/`native-path` == MAC; wired HID keyboards stay out), with a
  BlueZ Battery1 fallback. 30s refresh. Source:
  `assets/plasma/plasmoids/org.kde.mika.btbattery/`.
- Then a `panelSpacer` and a right-aligned `digitalClock` with custom date
  format `dd MMM yyyy`.

`displayStyle` is **not** the stock ksysguard `textonly` face. It is the
local fork `assets/plasma/ksysguard/sensorfaces/org.kde.mika.mutedtextonly`
(installed via `xdg.dataFile`) because:

- stock `textonly` pins label/value text to the theme's bright color;
- ksystemstats publishes only instantaneous 500ms rates.

The fork draws text in muted gray (`#a8a8a8`), groups related sensors into
one row, and keeps a 10s rolling average for the four network/disk **rate**
rows (suffixes `/download`, `/upload`, `/read`, `/write`); percentages stay
live. Used/total pairs (`*/used` + `*/total`, `*/usedVram` + `*/totalVram`)
render as one `used / total` value. The colored indicator is one per row and
can be hidden; the top bar sets `showIndicators = false` and
`groupSensors = true` in the face's `General` config group via
plasma-manager's `systemMonitor.settings`, so metrics are separated by
spacing only. Sensor colors are still declared (plasma-manager requires
them) but are unused while indicators are off.

Sensor IDs must be the ksystemstats paths. Verify live:

```
qdbus --literal org.kde.ksystemstats1 /org/kde/ksystemstats1 allSensors
```

(needs `--literal`; qdbus without it cannot print the hash type).
plasma-manager's `systemMonitor` module requires `color` + `label` on
**every** sensor (no defaults upstream).

## Scaling (`hosts/nixos/kscreen.nix`)

The host unit forces 200% on `HDMI-A-1` via
`kscreen-doctor output.HDMI-A-1.scale.2` and `kwinrc Xwayland.Scale=2`.

## Login maximize sweep (`home/kwin-remax.nix`)

`assets/kwin-remax/remax.js` is loaded at login via KWin Scripting D-Bus by
the `kwin-remax` user unit.

It touches **only** the REMAX app-id list (currently `seance`), Normal
windows, once each:

- force-maximizes arrivals — Wayland session restore drops the maximize
  flag; and
- re-applies maximize so geometry is computed after struts/kscreen settle.

It matches on `resourceClass` (this KWin build has **no** `appId` property —
reads `undefined`), and self-unloads after ~20s.

## Seance

The terminal multiplexer's keybinds and config symlink are described in
[seance](seance.md).

## Debugging notes

### 4K scaling at 200%

`kdeglobals ScaleFactor` does nothing on Wayland; kscreen owns per-output
scale. `hosts/nixos/kscreen.nix` re-asserts via an on-login user unit
(`kscreen-doctor output.HDMI-A-1.scale.2` + `kwinrc Xwayland.Scale=2`). If
the Display KCM shows a different %, the kscreen profile is winning — adjust
in the GUI or in the service.

### Wayland session restore drops maximize state (2026-11-09)

Login restores windows (positions; X11-SM apps like Emacs even with max=3)
but Wayland clients come back **unmaximized**. Seance arrived `max=0` out of
place at every login, invisible to the original remax sweep (that only
toggled windows already maximized; nothing "remembers" seance's state between
logouts).

Fix: the REMAX app-id list in `assets/kwin-remax/remax.js` (see above). A
blanket re-max was dropped 2026-11-09 — unlisted windows place fine on their
own.

To inspect window state live: load a dump script via

```
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript <file> <unique-name>
```

then run it; `print()` lands in `journalctl --user` under `kwin_wayland`.
Use a **unique** plugin name per probe (same name twice = `loadScript -1`).
Properties: `resourceClass`/`desktopFileName` work; `appId` reads
`undefined` even though the docs advertise it.

### Panel applet width from a compact representation (2026-11-16)

The panel sizes an applet from the Layout attached properties of the
compactRepresentation's **root** item, not from its `implicitWidth`
(libplasma `AppletQuickItem::connectLayoutAttached`). With async data the
first width is 0, and a centered row then spills over the left neighbour.
Bind `Layout.minimum/preferred/maximumWidth` to the content's
`implicitWidth` (plus `implicitWidth` for good measure) and anchor the
content left.

### Top-left still opened Overview with all hot corners "None" (2026-11-16)

`[ElectricBorders]` only maps the legacy built-in actions. Effects register
screen edges separately from their own config group, and the Overview
effect's kcfg defaults `[Effect-overview] BorderActivate` to
`ElectricTopLeft`. Pin it to `ElectricNone` (`9`) — see
[keyboard](keyboard.md#kwin-shortcuts-homeplasmanix).

### Keyboard KCM

The KDE Keyboard KCM can wipe NixOS-managed XKB options. See
[keyboard](keyboard.md#kde-keyboard-kcm-hijacks-xkb-options-2026-11-08).
