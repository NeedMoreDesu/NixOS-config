# Keyboard: XKB, keyd, xremap and KWin

The chain is **hardware → keyd → xremap → XKB/KWin**. Each layer has a
distinct job; moving a rule to the wrong layer breaks the ones above it.

| Layer | Owns |
| --- | --- |
| XKB (`modules/desktop.nix`) | Layout symbols and options only. |
| keyd (`modules/mac-keys.nix`, `assets/mac-keys/keyd.conf`) | The hold-layers XKB/xremap cannot express, plus the right-cmd → Menu rebind. |
| xremap (`modules/xremap.nix`, `assets/xremap/xremap.yml`) | The whole caps/ctrl/cmd cycle, app-aware keymaps, screenshots. |
| KWin (`home/plasma.nix`) | Window/session shortcuts (desktops, maximize, Overview, layout switching). |

## XKB layouts (`modules/desktop.nix`)

Plasma 6 with SDDM on Wayland, HiDPI enabled. Two layouts:

- `gb-mac-grave`
- `ua(unicode)`

Both are enabled together; Alt+Space cycles groups
(`grp:alt_space_toggle`). These are **XKB-native** options, so they also work
in the SDDM greeter.

`ua(unicode)` is the upstream r2u "Ukrainian Unicode" layout (not a local
addition). RAlt is level3: U+02BC apostrophe, `onglos`, ²/³, ₴, °, —/– and
other Slavic Cyrillics. The key left of `1` types `'` directly.

### `gb-mac-grave`

`assets/desktop/gb-mac-grave` is `gb(mac)` with one override: the §/± key
(left of `1`, `<TLDE>`) becomes grave/asciitilde. That lets xremap's
`F13-grave → Alt-grave` (Cmd+`) reach KWin as a real grave keysym instead of
typing §. It is otherwise plain `gb(mac)` again.

Note: `gb(mac)` also has `` ` ``/`~` on the key left of `Z` (`<LSGT>`); that
is left alone, so `` ` `` exists twice.

Right-cmd Hyper rides the upstream `caps:hyper` XKB **option**: the CapsLock
keycode maps to the `Hyper_L` keysym, and `hyper(mod3)` puts `Hyper_L` into
Mod3's keysym set. See [the Hyper history](#emacs-hyper-for-right-cmd-2026-11-08-closed).

Verify the layout with:

```
xkbcli compile-keymap --layout gb-mac-grave --test
```

after pointing `XKB_CONFIG_ROOT` at the generated `xkb.dir`.

## KWin shortcuts (`home/plasma.nix`)

The `shortcuts` block in `home/plasma.nix` owns a `kwin` group:

- Meta+Alt+Left/Right = switch desktop.
- Meta+Left/Right = quick-tile window left/right (KWin default).
- Meta+Up/Down = maximize / restore (`UntileOrRestoreOp`: un-fullscreen >
  un-tile > un-maximize; no-op on plain windows).
- Meta+Tab = Overview.
- The switcher's default secondary Meta+Tab / Meta+Shift+Tab bindings are
  stripped by re-asserting Alt+Tab[+Shift].
- Only the quick-tile Top/Bottom actions' **default** Meta+Up/Down bindings
  are pinned to `none`; KWin 6.5+ ships them on Meta+Up/Down, and without
  the pin Meta+Down fired Quick Tile Bottom instead of Window Restore.
  Left/Right are explicitly bound to Meta+Left/Right above.
- All 8 `kwinrc [ElectricBorders]` entries are pinned `None` — hot corners
  are off; Overview lives on the keyboard.

That pin only covers the legacy actions. The Overview **effect** has its own
`[Effect-overview] BorderActivate`, whose kcfg default is `ElectricTopLeft`
(top-left corner). It is pinned to `ElectricNone` (`9`, the same sentinel the
Screen Edges KCM writes for "No Action"), otherwise the corner still opened
Overview. Check other effects' `*.kcfg` for non-None defaults (windowview
already defaults to `ElectricNone`).

KWin caches `kwinrc` at startup. `nyx -k` calls `org.kde.KWin.reconfigure` +
`reconfigureEffect overview/windowview` so these changes apply without a
logout (see [rebuild](rebuild.md)). By hand:

```
qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure &&
qdbus org.kde.KWin /KWin /Effects \
  org.kde.kwin.Effects.reconfigureEffect overview
```

The title-bar middle button's toggle is Window Maximize (`MaximizeOp`), which
Meta+Up already carries.

Per-layout switching (Meta+Alt+1/2) is also declared in `home/plasma.nix`.
KWin names its per-layout switch actions from the symbols `name[Group1]`, not
the evdev.xml description — keep the shortcut keys in sync with those
strings.

## keyd (`modules/mac-keys.nix`)

keyd runs as a **minimal sidecar** under xremap. The module also sets the
`hid_apple.fnmode=2` kernel parameter (top row = F keys; brightness/sound on
Fn).

`assets/mac-keys/keyd.conf` keeps exactly its `swapm`/`maccycle` hold-layer:
Cmd+Tab / Cmd+grave emit Alt held for as long as Cmd is down. That is the one
thing xremap cannot express — KWin switcher popups need a physically-held
modifier. Cmd+Space moved to xremap.

### Option keys

`[main]`:

```
leftalt  = layer(alt)
rightalt = layer(alt)
```

Both options are plain Alt alone (switcher, Alt+Space toggle, menus).

Alt-characters are a **left-cmd chord**: `[meta]` has
`leftalt/rightalt = swap(altgr)`, so left cmd + either option switches keyd
to its built-in `altgr:G` layer for the next keys.

`swap`, **not** `layer(altgr)`: `[meta]` holds Super → xremap's virtual F13,
and a plain altgr layer would leave F13+RALT held, so xremap's inexact
`F13-<key>` rules would emit Ctrl-* instead of the level3 character. `swap`
sheds meta/Super first, so keyd emits a clean RALT+`<key>` and XKB level3
resolves it.

This has to happen at the keycode layer: `gb(mac)` **and** `ua` hard-wire
`level3(ralt_switch)` (RALT keycode = the alt-character layer, LALT = plain
Alt), and both keyd's `maccycle` and xremap's combos **emit** the LALT
keycode (bypassing keyd via the `0x0fac` skip). Swapping downstream with
`lv3:` XKB options would break every emitted Alt combo and
`grp:alt_space_toggle`.

keyd does not canonicalize alt (unlike `MOD_SUPER`), so RALT survives keyd.
The swap is banked on the Cmd keypress: Cmd **first**, then Option; AltGr
stays until Cmd is released (releasing Option first does not swap back).
Right cmd is Menu and does not enter `[meta]`, so the chord is left-cmd only.

### `rightmeta = menu`

keyd normalizes **both** cmd keys through the meta descriptor
(`src/keys.c`: `MOD_SUPER` → canonical `KEYD_LEFTMETA`), so `KEY_RIGHTMETA`
never reaches xremap and any Super_R rule behind keyd is dead code. `Menu`
is the only right-cmd output that stays distinguishable downstream, so keyd
has `rightmeta = menu` in `[main]` and xremap maps `Menu` → CapsLock (Emacs
block) or F13 (base).

Cost: right cmd no longer triggers `[meta]`, so swapm cycling is left-cmd
only.

Trap: bindings belong in `[main]`; `[global]` is config options only.
`rightmeta = menu` under `[global]` parses as a bogus option, warns, and does
nothing (`keyd check /etc/keyd/default.conf` catches it).

## xremap service (`modules/xremap.nix`)

`services.xremap` comes from `xremap-flake`:

- `serviceMode = "user"` — the upstream KDE-Wayland client refuses to run as
  root.
- `withKDE` for app-aware rules.
- `deviceNames = [ "keyd" ]` — grab **only** keyd's virtual device; keyd owns
  the hardware, and evdev grabs are exclusive.
- `extraArgs = [ "--vendor" "0x0fac" ]` — keyd's `is_virtual` skip. Without
  it keyd would grab xremap's output and the two would feed each other.
- `watch` re-attaches after keyd restarts.

It is a session-scoped user unit on `graphical-session.target`, so the SDDM
greeter gets vanilla keys plus keyd's hold-layer only.

There is **no live config reload**. `nyx` restarts the unit after a
successful switch (see [rebuild](rebuild.md)); a bad YAML then fails the unit
loudly.

## xremap policy (`assets/xremap/xremap.yml`)

The policy runs at the evdev layer **below XKB** (see
[the layering note](#xremap-layering-the-big-one)).

### `modmap` blocks

First-match, per key.

1. **Emacs block first.** The app regex **must** be `(?i)` — KWin reports the
   class as `Emacs`, and xremap regexes are case-sensitive; a mismatch means
   cmd silently falls through to the generic cycle.
   - Left cmd → F13; the Emacs keymap block re-emits every `F13+<key>` as
     `[F14, <key>]` (F14 = `XF86Launch5` in Emacs). The `s-` prefix binding is
     ELISP in the `~/.emacs.d` Prelude fork, not this repo.
   - Right cmd (arrives as `Menu` — keyd normalization, see above) →
     CapsLock → Hyper via the `caps:hyper` XKB option → `H-` in
     Emacs/XWayland.
   - Rollback of Hyper = delete the block + the XKB option + the keyd rebind.
2. **Generic cycle**: caps → ctrl, ctrl → super, cmd → F13 (F13 is a
   `virtual_modifiers` key, inert everywhere).

### `keymap` blocks

First match wins; app blocks precede the generic one.

- **Terminals** (`konsole`, `ghostty`, `seance`): explicit whitelist —
  c/v/x/f/t/w/n → `Ctrl+Shift-*`; left/right word-nav; backspace →
  `Ctrl-Delete`; up/down → `Ctrl-Home/End` (no Home/End keys on this board).
  Everything else is swallowed. That avoids duplicates of the caps-Ctrl
  bindings and the XOFF/EOF/SIGTSTP traps; C-i **is** Tab and C-j **is**
  Enter, so there are zero leaks.
- **Default**: nearly the whole alphabet → `Ctrl-*` (h/m unmapped on
  purpose; q → Alt+F4, space → Alt+F2 run dialog, 1/2 → Alt+Super+1/2 = KWin
  layout switch, up/down → Ctrl-Home/End, slash/enter/backspace/arrows).
  Shift variants (redo, reopen tab, force reload, …) come free via inexact
  matching.

There are **no** `F13-tab`/`F13-grave` rules: keyd consumes those before
xremap, and an extra rule would stack a second synthetic Alt on keyd's held
Alt_L (inexact matching).

### Screenshots

The screenshots block comes **first** (no app filter) so it wins in every
app, including Emacs and terminals:

| Binding | Action |
| --- | --- |
| Cmd+Shift+1 | Current window |
| Cmd+Shift+2 | Window under cursor |
| Cmd+Shift+3 | Full screen |
| Cmd+Shift+4 | Region |
| Cmd+Shift+5 | GUI (Spectacle) |
| Cmd+Shift+6 | Swallowed |

All go to `scripts/screenshot.sh`, which uses Spectacle background mode
(timestamped file in `~/Pictures/Screenshots` + image on the clipboard;
background mode ignores Spectacle's GUI save/clipboard settings, hence the
explicit `-o` + `-c`). This needs `--allow-launch true` in
`modules/xremap.nix`.

The script is passed as an **argument** to the absolute bash, not via
`bash -c /path/script`: the unit PATH has no bash, so a
`#!/usr/bin/env bash` shebang dies with exit 127. For the same reason the
script sets its own PATH and its shebang is the absolute
`/run/current-system/sw/bin/bash`.

## Debugging notes

### Cmd+` dead + stray § key

`gb/mac` types §/± on the key left of `1` (keycode 41). keyd fired
`grave = A-grave` on that *keycode*, so it sort-of worked, but only because
KWin matches the combo by keysym. Fixed at the layout level: the
`gb-mac-grave` layout includes `gb(mac)` and overrides `<TLDE>` to
grave/asciitilde (see above).

### xremap layering (the big one)

xremap reads and emits evdev **keycodes**, below XKB. Consequences:

1. XKB layout/options are invisible to its combo matching — it sees the
   physical CapsLock/LeftMeta regardless of what XKB maps them to.
2. Everything xremap emits is then remapped by XKB, so doing the
   caps/ctrl/cmd cycle in *both* layers corrupts xremap's emitted Ctrl (XKB
   would re-map it to Super). Hence the whole cycle lives in xremap's
   `modmap`; XKB only carries layout symbols.
3. `modmap` never chains its own output (single pass, first matching rule per
   input keycode): CapsLock→Control_L won't fall through the
   Control_L→Super_L rule.
4. `keymap` is first-match across blocks; app blocks before the generic one.
5. There are **no** `Meta_*` aliases in xremap — `KEY_LEFTMETA` is
   `Super_L`/`WIN_L`. A bad name fails `--validate-config`, reported at the
   *map start* line, not at the bad entry.
6. KDE Wayland: `--list-windows` is unsupported. App classes show up as
   `active window: caption..., class...` in `journalctl --user -u xremap`
   once any application-filtered rule has fired once (use a dummy-name
   filter to fish).

**General rule:** any per-side modifier rule behind keyd must go through a
keyd rebind, never through xremap's Super_R/Alt_R/etc. matching.

### Emacs Hyper for right cmd (2026-11-08, closed)

xremap speaks only evdev keycodes as output — `Hyper`/`Hyper_L` don't parse,
and one bad name fails the **whole** config load (unit dead until fixed; run
`xremap --validate-config` before trusting `nyx`, whose restart now makes
that loud).

Emacs (XWayland — check `ss -xp` its fds; class `Emacs` = XWayland
WM_CLASS) gets hyper from X's core modifier map: a mod group whose keysyms
include `Hyper_L`/`Hyper_R` → `H-`.

Final route: the Emacs `modmap` block emits CapsLock (keycode 58 — nothing
else ever produces it; the physical caps key is eaten by the cycle upstream)
plus the XKB option `caps:hyper`. It replaces `<CAPS>` with the `Hyper_L`
keysym and pulls in `hyper(mod3)` = `modifier_map Mod3 { <HYPR> }`, which
puts `Hyper_L` into Mod3's keysym set. X11 then depresses Mod3 for any key
producing that keysym, so right-cmd combos arrive as `H-` in Emacs.

Earlier custom attempt, superseded: `KEY_MACRO`/I120 bound in `gb-mac-grave`
compiled and XTEST-verified fine (`v` arrives with state `0x20`) yet Emacs
still behaved as Super. Root cause: keyd's cmd normalization (below) — the
Macro rule never actually fired. `KEY_MENU` (I147) was the first pick but
loses to `symbols/inet` (last section of the compiled chain; layout sections
cannot override later includes). XKB sections cannot span groups
(`name[Group2]` corrupts `gb(mac)`'s include — no upstream file does it);
options apply to all groups, another reason `caps:hyper` is the robust shape.

KDE caveat: Qt has no hyper modifier. KWin/Qt map the Hyper keysym to a
broken Meta (discuss.kde.org thread 13381, QTBUG-61301, KDE bug 379949), so
a bare right-cmd **tap** can pop the Plasma search launcher (the "Meta"
single-key shortcut). Combos are unaffected and reach Emacs as `H-`.
Upstream is inconsistent: xkeyboard-config issue #344 moved the
`ctrl:hyper_*` options from Mod3 to Mod4 (Super) in 2023, but `caps:hyper`
still includes `hyper(mod3)`. Native Wayland apps have no hyper bit in the
protocol, so they only ever see a tap.

Greeter side effect: without xremap the physical caps key is Hyper at SDDM
(caps-lock toggle gone there).

### KDE Keyboard KCM hijacks XKB options (2026-11-08)

System Settings → Keyboard → "Configure keyboard options" persists to
`~/.config/kxkbrc`; kxkb then applies **its** option list over the system's
`XKB_DEFAULT_OPTIONS`. Merely toggling the box briefly left
`ResetOldOptions=true` with an empty list, which wiped every option (Alt+Space
layout switching died, `caps:hyper` never reached KWin). KWin reads `kxkbrc`
at session start only — no hot reload.

Fix: delete `kxkbrc`, log out/in; env options return.

Rule: XKB options are NixOS-managed (`modules/desktop.nix`) — hands off that
KCM. If it must be used, re-check everything; it overrides wholesale.

Related gotcha: right-cmd showing as `S-v` in Emacs while the option was dead
was **not** Super — that is plain Caps_Lock rendering (lock shifts the
keysym v → V and Emacs prints it `S-`).

### keyd eats the left/right cmd distinction (2026-11-08)

Every "right cmd behaves like left cmd" symptom traced back to keyd, not
XKB/xremap/KWin: keyd binds both cmd keys to the *meta descriptor alias* and
re-emits modifiers from a canonical table (`src/keys.c`:
`{MOD_SUPER, KEYD_LEFTMETA}`). `KEY_RIGHTMETA` never leaves keyd's virtual
device, so xremap's Super_R rules were dead code in both hyper eras (the
Macro/I120 "mystery failure" included: Macro never fired; the launcher taps
were plain Super).

Fix: `rightmeta = menu` in keyd `[main]` — a plain key keeps its identity
through the chain; xremap then maps `Menu` (CapsLock in Emacs / F13
elsewhere).

Also: evdev grabs are **exclusive**. `evtest` on event17/event22
(keyd/xremap devices) just prints "device is grabbed by another process";
passive chain snooping while the stack runs is impossible. Go through the X
side (`xev`) or reason from source. `keyd monitor` prints per-device raw +
processed events and is the way to see what the Magic Keyboard actually
sends.

### New group membership + the user manager

Adding mika to `input`/`uinput` groups doesn't take effect on logout/login
alone: the `systemd --user` instance survives if **any** process holds the
slice (long-running shells like opencode do) and keeps its launch-time
credentials. Check `loginctl user-status`: a slice "Since:" predating the
logout proves it. `systemctl --user daemon-reexec` will not re-read groups
either.

Symptom: xremap EPERMs on `/dev/input` + `/dev/uinput` even though
`getent group` and the node perms look right — compare `id` (stale session
credentials) with `getent` (DB truth).

Fix: **reboot**. Don't `loginctl terminate-user` (SDDM 0.21 black-VT trap,
see [rebuild](rebuild.md)).

### xremap `launch` + script shebang (2026-11-15)

Cmd+Shift+1/2/3/4/5 did nothing while every other F13 combo worked. The rules
launched
`/run/current-system/sw/bin/bash -c /home/mika/nixos_config/scripts/screenshot.sh ...`;
the script's `#!/usr/bin/env bash` shebang is resolved by `/usr/bin/env`
against the **launch child's PATH — xremap's unit PATH, which has no bash**
(xremap/systemd/coreutils only). Result: `env: 'bash': No such file or
directory`, exit 127, before the script body, and xremap discards the child's
stdout/stderr (`Stdio::null`), so it was completely silent.

An inline `bash -c 'touch ...'` probe worked; the same script run from a
normal terminal worked; `env -i PATH="<unit PATH>" /usr/bin/env bash`
reproduces the 127.

Fix: pass the script as bash's **argument** (`bash /path/screenshot.sh full`),
which bypasses the shebang, and make the shebang the absolute
`/run/current-system/sw/bin/bash`.

**General rule:** xremap launch children are not your shell — no bash in
PATH, and their stderr is thrown away.

### Stuck keys when a device disappears (2026-11-22)

keyd 2.6.0's `EV_DEV_REMOVE` handler only logs the removal. A key held
when the Bluetooth link times out never gets its key-up, so it stays down
on keyd's virtual device forever. The local patch
`patches/keyd-release-on-remove.patch` (applied in `modules/mac-keys.nix`)
implements `kbd_reset()` and calls it plus `clear_vkbd()` on removal:
release everything keyd emitted, clear held layers/chords/pending
timeouts. Drop the patch when upstream keyd does this itself.

The `[ids] *` wildcard means all keyboards share one remapper state, so a
removal resets that shared state. With one BT keyboard that is exactly
what we want; a second keyboard held at that moment would also be
released (the physical key re-sends its down if still held).

2026-11-22 regression: the first version of `kbd_reset()` zeroed
`kbd->layer_state[0]` along with the transient layers. Layer 0 is the
always-active main layer (`new_keyboard()` sets `active = 1`; upstream
`clear()` starts at index 1), so after any removal keyd fell back to
pass-through: it kept running and xremap kept its vkbd grabbed, but the
`[main]` mappings (`meta`/`alt`/`altgr` layer activators, `rightmeta =
menu`) and the Cmd+Tab/grave hold-layer were dead until keyd restarted.
The patch now resets only layers above 0 and explicitly restores layer
0's `active`/`activation_time`; the key-release logic in `clear()` and
`clear_vkbd()` is unchanged. `scripts/keyboard_restart.sh` remains a
recovery tool for genuinely wedged states, not the fix for this one.

This only covers devices keyd **grabs**. The last logger run caught the
Magic Keyboard's `f13` stuck on the USB interface
`05ac:029c:cde6b8ac`, which keyd logs as `DEVICE: ignoring`; keyd never
owns it, so it cannot release that key. That case is the keyboard's own
reported state; unplug/replug the keyboard (or reset its USB device) is
the practical recovery.

### Bluetooth link timeouts (2026-11-22)

The Magic Keyboard is classic BR/EDR HIDP over the Realtek RTL8922AE
combo card. The card exposes Bluetooth as a USB device (`13d3:3617`,
`Bluetooth Radio`, USB path `1-6`) even though the antenna is external;
the Wi-Fi half is PCIe. The `2026-11-21` logger run showed repeated
`Disconnect Complete ... Reason: Connection Timeout (0x08)` with a 32 s
supervision timeout and 122 HIDP `GET_REPORT` timeouts, with no A2DP
gaps, so A2DP coexistence is not required for the failure.

`modules/bluetooth.nix` sets `btusb.enable_autosuspend=0` to keep that
controller out of USB runtime autosuspend. The adapter was already
`active` during the captured stalls (`runtime_suspended_time` did not
move), so this is an A/B test, not a confirmed fix. The battery still
reads 100% with no voltage/health, so a weak cell/power problem remains
plausible; see `~/temp/keyboard_issues/plan.md` for the capture kit.

## Closed experiments

- [Toshy](history/toshy.md) — rolled back.
- [pasteboard](history/pasteboard.md) — Cmd+C/V experiment, closed.