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
       # runs: nixos-rebuild switch --flake ~/nixos_config#nixos,
       # then restarts the xremap user unit (no live config reload
       # there; runuser + XDG_RUNTIME_DIR so systemctl --user reaches
       # MIKA's manager, not root's — a bad yml now surfaces loudly
       # as a failed unit instead of silently stale keys)
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
flake.nix              inputs: nixpkgs, llm-agents, home-manager, plasma-manager,
                       seance (git+https + ?submodules=1 for vendored ghostty;
                       inputs.nixpkgs.follows = "nixpkgs" so it builds against
                       our closure), xremap-flake (github:xremap/nix-flake:
                       NixOS/HM module + its own pinned xremap build; NOT
                       following nixpkgs — same policy as llm-agents),
                       workmux. Passed to modules via specialArgs.
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
                        so xremap's `F13-grave -> Alt-grave` (Cmd+`) reaches KWin as
                                                 a real grave keysym instead of typing §. gb-mac-grave
                         also binds <I120> (KEY_MACRO, emitted ONLY by xremap's
                         emacs block) to Hyper_L + modifier_map Mod3 -> Emacs
                         hyper (H-); I120 is the one keycode unbound across the
                         whole compiled chain (KEY_MENU/I147 loses to
                         symbols/inet, the last section). ua(unicode) IS the r2u
                       "Ukrainian Unicode" layout, upstream since forever (RAlt =
                       level3: U+02BC apostrophe, onglos, ²/³, ₴, °, —/–, other
                       Slavic Cyrillics; key left of 1 types ' directly).
                       KWin names its per-layout switch actions from the symbols
                       name[Group1], not the evdev.xml description — keep the
                       home.nix shortcut keys in sync with those strings.
  mac-keys.nix         keyd as a MINIMAL sidecar under xremap + the
                       hid_apple.fnmode=2 kernel param (top row = F keys,
                       brightness/sound on Fn). keyd keeps exactly its
                       swapm/maccycle hold-layer (Cmd+Tab / Cmd+grave emit
                       Alt held for as long as Cmd is down — the one thing
                       xremap cannot express; KWin switcher popups need a
                       physically-held modifier). Cmd+Space moved to xremap.
                       chain: hardware -> keyd -> xremap -> KWin.
  xremap.nix           services.xremap (from xremap-flake): serviceMode = "user"
                       (the upstream KDE-Wayland client refuses to run as root),
                       withKDE for app-aware rules, deviceNames = [ "keyd" ]
                       (grab ONLY keyd's virtual device — keyd owns the hardware;
                       evdev grab is exclusive), extraArgs = [ "--vendor"
                       "0x0fac" ] (keyd's is_virtual skip: without it keyd would
                       grab xremap's output and the two would feed each other),
                       watch (re-attach after keyd restarts).
                       Session-scoped user unit on graphical-session.target —
                       the SDDM greeter gets vanilla keys + keyd's hold-layer
                        only. No live config reload: nyx restarts the unit
                        itself after a successful switch.
  xremap.yml           the keyboard policy, at the evdev layer BELOW XKB (see the
                       layering note under debugging). modmap blocks are
                        first-match per key: EMACS block first (app regex
                        MUST be (?i) — KWin reports class 'Emacs' and
                        xremap regexes are case-sensitive: mismatch = cmd
                        silently goes F13 through the generic cycle);
                        left cmd identity -> real Super (s- space), right
                        cmd -> KEY_MACRO "Macro" -> XKB Hyper_L on Mod3 ->
                        H- in Emacs/XWayland (see gb-mac-grave + the
                        debugging note); rollback = delete the block AND
                        the I120 binding), then the
                       generic cycle caps->ctrl, ctrl->super, cmd->F13 (F13 =
                       virtual_modifiers, inert everywhere). keymap (first match
                       wins, app blocks first): terminals (konsole/ghostty/
                       seance) = explicit whitelist: c/v/x/f/t/w/n ->
                       Ctrl+Shift+*, left/right word-nav, backspace ->
                       Ctrl-Delete, up/down -> Ctrl-Home/End (no Home/End keys
                       on this board), everything else swallowed (dupes of the
                       caps-Ctrl + XOFF/EOF/SIGTSTP traps; C-i IS Tab, C-j IS
                       Enter — zero leaks); default = nearly the whole alphabet
                       -> Ctrl+* (h/m unmapped on purpose; q -> Alt+F4, space
                       -> Alt+F2 run dialog, 1/2 -> Alt+Super+1/2 = KWin layout
                       switch, up/down -> Ctrl-Home/End, slash/enter/
                       backspace/arrows). Shift variants (redo, reopen tab,
                       force reload...) come free via inexact matching.
                       NO F13-tab/F13-grave rules: keyd consumes those before
                       xremap, and an extra rule would stack a second synthetic
                       Alt on keyd's held Alt_L (inexact matching).
  audio.nix            PipeWire (pulse compat), rtkit
  bluetooth.nix        BT stack + bluetooth-reconnect service (see below)
  printing.nix         CUPS
  users.nix            mika: wheel+NM, kate/emacs
  packages.nix         firefox + git, sourcegit, godot, krita, librewolf;
                       steam via programs.steam (FHS sandbox, steam-hardware,
                       32-bit PipeWire). allowUnfreePredicate scoped to the
                       "steam" name prefix (steam pulls steam-run etc.).
                       seance (scrolling GTK4/libadwaita terminal multiplexer
                       that tracks AI coding agents; MIT, Zig 0.16) comes from
                       the seance flake input, NOT nixpkgs:
                       seance.packages.${pkgs.system}.seance.
  nix.nix              nix-command + flakes; weekly GC (--delete-older-than 14d)
                       + weekly store optimise via nix-gc/nix-optimise timers
  llm-agents.nix       numtide cache (binary substituter) + opencode + dsh
  home-manager.nix     HM wiring: useGlobalPkgs, users.mika -> hosts/nixos/home.nix
```

## Things that took debugging

- **4K scaling at 200%**: `kdeglobals ScaleFactor` does nothing on Wayland; kscreen owns per-output scale. `home.nix` re-asserts via on-login unit `kscreen-doctor output.HDMI-A-1.scale.2` + `kwinrc Xwayland.Scale=2`. If Display KCM shows a different %, kscreen profile is winning — adjust in GUI or the service.
- **Bluetooth peripherals dead at boot**: BlueZ doesn't page paired devices after adapter start. `bluetooth-reconnect` service pages *every* paired device until all show `Connected: yes`. Paging is async per device — one background `bluetoothctl connect` job each (BlueZ queues the pages itself), max 8 attempts per device so a powered-off one doesn't drag the loop; a serial connect would stall everything behind the first unresponsive device. Runs `Type=simple`: activation waits for oneshot start jobs, which used to block `nyx` for minutes. Devices themselves are fine — they accept paging while asleep. Caveat: in-range headphones get pulled in too.
- **Cmd+` dead + stray § key**: gb/mac types §/± on the key left of 1 (keycode 41). keyd fired `grave = A-grave` on that *keycode*, so it sort-of worked, but only because KWin matches the combo by keysym. Fixed at the layout level: extraLayouts.gb-mac-grave includes gb(mac) and overrides <TLDE> to grave/asciitilde. Note gb/mac also has ` / ~ on the key left of Z (<LSGT>) — left alone, so ` exists twice. Verify with `xkbcli compile-keymap --layout gb-mac-grave --test` after pointing XKB_CONFIG_ROOT at xkb.dir.
- **New group membership + the user manager**: adding mika to input/uinput groups doesn't
  take effect on logout/login alone — the `systemd --user` instance (check `loginctl
  user-status`: slice "Since:" predates the logout) survives if ANY process holds the slice
  (tmux/opencode shells do), and keeps its launch-time credentials. `systemctl --user
  daemon-reexec` won't re-read groups either. Symptom: xremap EPERMs on /dev/input +
  /dev/uinput even though `getent group` and the node perms are right — compare `id` (stale
  session creds) vs `getent` (DB truth). Fix: REBOOT. Don't `loginctl terminate-user`:
  SDDM 0.21 black-VT trap (see bluetooth note's helper-exit caveat).
- **xremap layering (the big one)**: xremap reads and emits evdev *keycodes*, below XKB. Consequences: (1) XKB layout/options are invisible to its combo matching — it sees the physical CapsLock/LeftMeta regardless of what xkb maps them to; (2) everything xremap emits is then remapped by XKB, so doing the caps/ctrl/cmd cycle in BOTH layers corrupts xremap's emitted Ctrl (XKB would re-map it to Super). Hence the whole cycle lives in xremap's modmap and XKB only carries layout symbols. (3) modmap never chains its own output (single pass, first matching rule per input keycode) — CapsLock->Control_L won't fall through the Control_L->Super_L rule; (4) keymap is first-match across blocks — app blocks before the generic one; (5) there are NO `Meta_*` aliases in xremap — KEY_LEFTMETA is `Super_L`/`WIN_L` (a bad name fails --validate-config, reported at the *map start* line, not the bad entry); (6) KDE Wayland: `--list-windows` unsupported — app classes show up as `active window: caption..., class...` in `journalctl --user -u xremap` once any application-filtered rule has fired once (use a dummy-name filter to fish).
- **Emacs Hyper for right cmd (2026-11-08)**: xremap speaks only evdev keycodes
  as OUTPUT — `Hyper`/`Hyper_L` don't parse, and one bad name fails the WHOLE
  config load (unit dead until fixed; `xremap --validate-config` before
  trusting nyx, whose restart now makes that loud). Emacs (XWayland — check:
  `ss -xp` its fds, class 'Emacs' = XWayland WM_CLASS) gets hyper from X's
  core modifier map: a mod group whose keysyms include Hyper_L/Hyper_R -> H-.
  Route: emacs modmap block emits KEY_MACRO (evdev 112 -> XKB <I120>),
  gb-mac-grave binds it to Hyper_L + `modifier_map Mod3`. KEY_MENU (I147) was
  the obvious pick but LOSES: symbols/inet is the last section of the compiled
  chain (pc+layouts+options+inet(evdev)) and binds it to XF86MenuKB — layout
  sections can't override later includes (`replace` too late, options too
  early), so only an otherwise-unbound keycode wins (inet's KEY_MACRO line is
  commented out upstream). Two rabbit holes: XKB sections can't span groups
  (name[Group2] duplicates gb(mac) into group 2 and breaks the compile — no
  upstream file ever declares one; plain Group2 refs are silently clipped),
  so the binding lives in group 1 only — Emacs reads the modmap per-keycode,
  H- should survive the ua toggle (RE-VERIFY, and re-verify that native
  Wayland apps can't see any of this: no hyper bit in the protocol).
- **llm-agents input**: do NOT add `follows = "nixpkgs"` — their binaries in `cache.numtide.com` are built against their own pinned nixpkgs; following yours = cache misses + rebuilds.
- `/etc/nixos/` is obsolete; the repo is the source of truth.

## Next steps (not done yet)

- **xremap experiment (this branch, 2026-11-08)**: the cycle + Cmd combos
  work post-reboot (see group gotcha). Cmd+Tab/grave gap solved by keeping
  keyd as a hold-layer sidecar under xremap (mac-keys.nix / xremap.nix
  chain notes). EMACS block fixed ((?i)emacs — the silent case-sensitivity
  miss that leaked F13 into Emacs) and now maps left cmd = Super (s-),
  right cmd = Macro -> Hyper_L/Mod3 via gb-mac-grave (H-, see the new
  debugging note). PENDING: `nyx` (it restarts the xremap unit itself now),
  log out/in (KWin compiles the xkb keymap at session start — the I120
  binding needs a fresh session), then verify: xremap's journal grabbed ONLY
  the keyd device (no hardware), Cmd+Tab/grave cycle with the popup held,
  Cmd+c/v/... still xremap-driven, and in Emacs `C-h k`: left cmd+v -> s-v,
  right cmd+v -> H-v, ALSO with the ua layout active (group-1-only
  binding caveat). Later: fish real konsole/ghostty/seance class strings
  via the journalctl dummy-filter trick and tighten the regexes (same
  case-sensitivity trap may lurk there too).

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
