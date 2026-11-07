# short_summary.md

Entry point for this machine's NixOS config. Repo: `~/nixos_config` (git-tracked; the flake only sees committed/staged files, so `git add` before rebuilding after adding new files).

Mode of operations for AI assistants: commit incrementally — each finished change gets its own commit right away, don't batch up edits and don't wait to be asked.

## What this system is

- NixOS unstable (`nixpkgs#nixos-unstable`), host `nixos`, single machine
- KDE Plasma 6 + SDDM (Wayland), PipeWire, CUPS, NetworkManager, Bluetooth
- User `mika`; AI CLIs (`opencode`, DeepSeek `dsh`) from numtide's llm-agents.nix

## How to rebuild

```
nyx    # alias -> sudo bash ~/nixos_config/rebuild.sh
       # runs: nixos-rebuild switch --flake ~/nixos_config#nixos
nyxx   # same, but first: nix flake update --commit-lock-file
       # (runs as you, not root; commits the lockfile itself)
        # flags: -u/--update does the flake update, -r/--reboot reboots
        # after a successful switch, -l/--logout ends the KDE session
        # instead (qdbus org.kde.Shutdown /Shutdown logout as the user —
        # plasma-shutdown replaced the ksmserver logout slot Plasma 6.8
        # dropped; session ends from inside so SDDM returns to the
        # greeter. loginctl terminate-user is broken with SDDM 0.21:
        # HUP-killed sddm-helper reads as exit 1 = HELPER_AUTH_ERROR and
        # the greeter never restarts — black VT. KWin re-reads session
        # bits on login; -r wins if both are given). Flags combine,
        # e.g. nyx -u -r
```

Update pins: `nix flake update <input>` (git needed; `sudo`-free shell may lack git until systemPackages rebuild lands — `nix-shell -p git` works).

## Layout

```
flake.nix              inputs: nixpkgs, llm-agents, home-manager, plasma-manager
                       nixosSystem passes inputs to modules via specialArgs
rebuild.sh             one-liner flake rebuild
hosts/nixos/
  default.nix          host entry: imports modules + hardware-configuration.nix,
                       system.stateVersion = "26.05" (NEVER bump, see comment)
  hardware-configuration.nix   generated at install; machine-specific mounts
  home.nix             home-manager user config for mika (plasma-manager)
modules/               one topic per file:
  boot.nix             systemd-boot + EFI, configurationLimit 20
  networking.nix       hostname, NetworkManager
  locale.nix           Europe/Dublin, en_IE, console keymap ie
  desktop.nix          Plasma 6, SDDM (HiDPI on), xkb layouts: gb-mac-grave +
                       ua(unicode) with Alt+Space cycling (grp:alt_space_toggle;
                       xkb-native so it works in SDDM too). KWin's per-layout
                       actions get Meta+Alt+1/2 via home.nix `shortcuts`.
                       gb-mac-grave = gb(mac) with the §/± key (left
                       of 1) overridden to grave/asciitilde (modules/xkb-gb-mac-grave),
                       so keyd's maccycle `grave = A-grave` (Cmd+`) reaches KWin as a
                       real grave keysym instead of typing §. ua(unicode) IS the r2u
                       "Ukrainian Unicode" layout, upstream since forever (RAlt =
                       level3: U+02BC apostrophe, onglos, ²/³, ₴, °, —/–, other
                       Slavic Cyrillics; key left of 1 types ' directly).
                       KWin names its per-layout switch actions from the symbols
                       name[Group1], not the evdev.xml description — keep the
                       home.nix shortcut keys in sync with those strings.
  mac-keys.nix         keyd: NO blanket Cmd->Ctrl (removed deliberately). Cmd is a
                        real Meta except for three explicit bindings on the built-in
                        [meta] layer: Cmd+Tab / Cmd+` cycle KWin switchers with Alt
                        held via swapm into [maccycle:A] (the hold-layer lives as
                        long as Cmd is down); Cmd+Space -> dashboard (A-f1).
                        Everything else is plain Super+key — inert in most apps;
                        Ctrl+C/^R keep terminal semantics physically.
                        Also fnmode=2: top row = F keys, brightness/sound on Fn.
  audio.nix            PipeWire (pulse compat), rtkit
  bluetooth.nix        BT stack + bluetooth-reconnect service (see below)
  printing.nix         CUPS
  users.nix            mika: wheel+NM, kate/emacs
  packages.nix         firefox, git
  nix.nix              nix-command + flakes; weekly GC (--delete-older-than 14d)
                       + weekly store optimise via nix-gc/nix-optimise timers
  llm-agents.nix       numtide cache (binary substituter) + opencode + dsh
  home-manager.nix     HM wiring: useGlobalPkgs, users.mika -> hosts/nixos/home.nix
```

## Things that took debugging

- **4K scaling at 200%**: `kdeglobals ScaleFactor` does nothing on Wayland; kscreen owns per-output scale. `home.nix` re-asserts via on-login unit `kscreen-doctor output.HDMI-A-1.scale.2` + `kwinrc Xwayland.Scale=2`. If Display KCM shows a different %, kscreen profile is winning — adjust in GUI or the service.
- **Bluetooth peripherals dead at boot**: BlueZ doesn't page paired devices after adapter start. `bluetooth-reconnect` service pages *every* paired device until all show `Connected: yes`. Paging is async per device — one background `bluetoothctl connect` job each (BlueZ queues the pages itself), max 8 attempts per device so a powered-off one doesn't drag the loop; a serial connect would stall everything behind the first unresponsive device. Runs `Type=simple`: activation waits for oneshot start jobs, which used to block `nyx` for minutes. Devices themselves are fine — they accept paging while asleep. Caveat: in-range headphones get pulled in too.
- **Cmd+` dead + stray § key**: gb/mac types §/± on the key left of 1 (keycode 41). keyd fired `grave = A-grave` on that *keycode*, so it sort-of worked, but only because KWin matches the combo by keysym. Fixed at the layout level: extraLayouts.gb-mac-grave includes gb(mac) and overrides <TLDE> to grave/asciitilde. Note gb/mac also has ` / ~ on the key left of Z (<LSGT>) — left alone, so ` exists twice. Verify with `xkbcli compile-keymap --layout gb-mac-grave --test` after pointing XKB_CONFIG_ROOT at xkb.dir.
- **llm-agents input**: do NOT add `follows = "nixpkgs"` — their binaries in `cache.numtide.com` are built against their own pinned nixpkgs; following yours = cache misses + rebuilds.
- `/etc/nixos/` is obsolete; the repo is the source of truth.

## Next steps (not done yet)

- Rollback/GC: weekly nix-gc timer prunes profile generations >14d; boot menu capped at 20 entries. No `system.copySystemConfiguration` needed with a git repo
- No home.file/packages in HM yet — Plasma scaling + panel declared
- **Toshy rolled back** (too heavyweight, and it can't solve the Emacs copy/paste case
  cleanly — Cmd→Ctrl is a blanket GUI modmap, so Cmd+C lands as literal keyboard-quit in
  Emacs). keyd is back, now WITHOUT the blanket Cmd->Ctrl map (the swapm/maccycle
  hold-layer rework + clipboard policy pin were picked from the `pasteboard` branch;
  Cmd+C/V/X are plain Super+key since then — inert by design).
- **pasteboard experiment — closed.** The Cmd+C live-copy daemon and the Cmd+V
  paste verb (KWin fake_input keysym typing) both live on the `pasteboard` branch
  with the full design history in its DESIGN.md (§13–15). v4 was closed 2026-11-07:
  typing real keysyms while Cmd is down has unforeseeable consequences in
  consumers (Enter/Tab semantics differ per app), and Cmd+C alone isn't useful.
  Don't resurrect on master — everything keyboard-relevant was picked from it.
