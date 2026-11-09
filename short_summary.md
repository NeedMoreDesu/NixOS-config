# short_summary.md

Entry point for this machine's NixOS config. Repo: `~/nixos_config` (git-tracked; the flake only sees committed/staged files, so `git add` before rebuilding after adding new files).

Mode of operations for AI assistants: commit incrementally — each finished change gets its own commit right away, don't batch up edits and don't wait to be asked.

## What this system is

- NixOS unstable (`nixpkgs#nixos-unstable`), host `nixos`, single machine
- KDE Plasma 6 + SDDM (Wayland), PipeWire, CUPS, NetworkManager, Bluetooth
- User `mika`; AI CLIs (`opencode`, DeepSeek `dsh`) from numtide's llm-agents.nix
- Emacs config = its own repo: a Prelude fork in `~/.emacs.d` (GitHub,
  auto-cloned by home.nix on first activation)

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
   kwin-remax.js        login sweep loaded via KWin Scripting D-Bus by the
                        kwin-remax user unit (home.nix): re-applies the
                        maximize state of restored-maximized windows so
                        geometry is computed after struts/kscreen settle, AND
                        force-maximizes POLICY_MAXIMIZE app-ids (seance) that
                        arrive unmaximized. Matches on resourceClass (this
                        KWin build has NO appId property - reads undefined);
                        self-unloads after ~20s. See debugging note below.
    home.nix             home-manager user config for mika (plasma-manager;
                        left panel: keyboardlayout is a STANDALONE panel
                        widget with displayStyle=flag — tray-nested widgets
                        cannot be configured, plasma-manager items.configs
                        is dead code upstream, issue #504;
                        also clones ~/.emacs.d from the GitHub prelude fork
                       on first activation — one-time setup, never touches
                       the tree afterwards; upstream remote added for pulls.
                       The emacs keyboard elisp lives in THAT repo)
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
                         is otherwise plain gb(mac) again; right-cmd Hyper
                         rides the upstream caps:hyper OPTION (options line
                         above): CapsLock keycode -> Hyper_L keysym +
                         hyper(mod3) puts Hyper_L in Mod3's keysym set. ua(unicode) IS the r2u
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
                        rightmeta = menu rebind (2026-11-08): keyd normalizes
                        BOTH cmd keys through the meta descriptor (src/keys.c:
                        MOD_SUPER -> canonical KEYD_LEFTMETA), so KEY_RIGHTMETA
                        never reaches xremap and any Super_R rule behind keyd is
                        dead code; Menu is the only right-cmd output that stays
                        distinguishable downstream. xremap maps Menu -> CapsLock
                        (emacs block) / F13 (base). COST: right cmd no longer
                        triggers [meta], swapm cycling = left cmd only.
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
                         left cmd -> F13 + the emacs keymap block re-emits
                         every F13+<key> as [F14, <key>] (F14 = XF86Launch5
                         in Emacs; the s- prefix binding is ELISP in the
                         ~/.emacs.d prelude fork, not this repo — Emacs-side
                         keyboard work happens there); right
                         cmd (arrives as Menu — keyd normalization, see
                         mac-keys.nix) -> CapsLock -> Hyper via the
                         caps:hyper XKB option (desktop.nix) ->
                        H- in Emacs/XWayland; rollback = delete the block
                        + the option + the keyd rebind), then the
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
- **Emacs Hyper for right cmd (2026-11-08, closed)**: xremap speaks only evdev keycodes
  as OUTPUT — `Hyper`/`Hyper_L` don't parse, and one bad name fails the WHOLE
  config load (unit dead until fixed; `xremap --validate-config` before
  trusting nyx, whose restart now makes that loud). Emacs (XWayland — check:
  `ss -xp` its fds, class 'Emacs' = XWayland WM_CLASS) gets hyper from X's
  core modifier map: a mod group whose keysyms include Hyper_L/Hyper_R -> H-.
  FINAL ROUTE: emacs modmap block emits CapsLock (keycode 58 — nothing else
  ever produces it, the physical caps key is eaten by the cycle upstream of
  it) + the XKB option `caps:hyper`: it replaces <CAPS> with the Hyper_L
  keysym and pulls in `hyper(mod3)` = `modifier_map Mod3 { <HYPR> }`, which
  puts Hyper_L into Mod3's keysym SET — X11 then depresses Mod3 for ANY key
  producing that keysym, so right-cmd combos arrive as H- in Emacs. The
  earlier custom attempt (KEY_MACRO/I120 bound in gb-mac-grave) compiled and
  XTEST-verified fine (v arrives with state 0x20) yet Emacs still behaved as
  Super — root cause: keyd's cmd normalization (next bullet), the Macro rule
  never actually fired. Superseded; the layout binding is removed. KEY_MENU (I147) was the
  first pick but loses to symbols/inet (last section of the compiled chain;
  layout sections can't override later includes). XKB sections can't span
  groups (name[Group2] corrupts gb(mac)'s include — no upstream file does
  it); options apply to ALL groups, another reason caps:hyper is the robust
  shape. KDE caveat (the real head-scratcher): Qt has NO hyper modifier —
  KWin/Qt map the Hyper keysym to a broken Meta (discuss.kde.org thread
  13381, QTBUG-61301, KDE bug 379949), so a bare right-cmd TAP can pop the
  Plasma search launcher (the "Meta" single-key shortcut); combos are
  unaffected and reach Emacs as H-. Upstream itself is inconsistent here:
  xkeyboard-config issue #344 moved the ctrl:hyper_* options from Mod3 to
  Mod4 (=Super!) in 2023 — caps:hyper still includes hyper(mod3). Native
  Wayland apps: no hyper bit in the protocol, they only ever see a tap.
  Greeter side effect: without xremap the physical caps key is Hyper at
  SDDM (caps-lock toggle gone there).
- **KDE Keyboard KCM hijacks xkb options (2026-11-08)**: System Settings →
  Keyboard → "Configure keyboard options" persists to `~/.config/kxkbrc` and
  kxkb then applies ITS option list over the system's `XKB_DEFAULT_OPTIONS`
  — toggling the box even briefly left `ResetOldOptions=true` with an empty
  list, which WIPED every option (Alt+Space layout switching died,
  caps:hyper never reached KWin). KWin reads kxkbrc at session start only —
  no hot reload. Fix: delete kxkbrc, log out/in; env options return. Rule:
  xkb options are NixOS-managed (desktop.nix) — hands off that KCM; if it
  must be used, re-check everything there, it overrides wholesale.
  Related gotcha: right-cmd showing as `S-v` in Emacs while the option was
  dead was NOT super — that's plain Caps_Lock rendering: lock shifts the
  keysym (v -> V) and Emacs prints it `S-`.
- **keyd eats the left/right cmd distinction (2026-11-08, the real villain)**:
  every "right cmd behaves like left cmd" symptom traced back to keyd, not
  XKB/xremap/KWin: keyd binds both cmd keys to the *meta descriptor alias*
  and re-emits modifiers from a canonical table (src/keys.c:
  `{MOD_SUPER, KEYD_LEFTMETA}`) — KEY_RIGHTMETA never leaves keyd's virtual
  device, so xremap's Super_R rules were dead code in BOTH hyper eras (the
  Macro/I120 "mystery failure" included: Macro never fired; the launcher
  taps were plain Super). Fix: `rightmeta = menu` in keyd [global] — a
  plain key keeps its identity through the chain; xremap then maps Menu
  (CapsLock in emacs / F13 elsewhere). General rule: any per-side modifier
  rule behind keyd must go through a keyd rebind, never through xremap's
  Super_R/Alt_R/etc. matching. Also: evdev grab is EXCLUSIVE — evtest on
  event17/event22 (keyd/xremap devices) just prints "device is grabbed by
  another process"; passive chain snooping while the stack runs is
  impossible, go through the X side (xev) or reason from source. keyd
  section trap found the same day: BINDINGS belong in `[main]`; `[global]`
  is config-options only — `rightmeta = menu` under [global] parsed as a
  bogus option, WARNED (`keyd check /etc/keyd/default.conf`), and did
  nothing — which is how the user's "Super_L rebind moves both cmd keys
  together" test reproduced the normalization despite the fix being
  committed. `keyd monitor` prints per-device raw+processed events and is
  the way to see what the Magic Keyboard actually sends.
- **Wayland session restore drops maximize state (2026-11-09)**: login restores
  windows (positions, X11-SM apps like emacs even with max=3) but Wayland
  clients come back UNMAXIMIZED — seance arrived max=0 out of place every
  login, invisible to the original remax sweep (it only toggles windows that
  are already maximized; nothing "remembers" seance's state between logouts).
  Fix = positive policy in kwin-remax.js: POLICY_MAXIMIZE app-ids get
  force-maximized by the sweep. To inspect window state live: load a dump
  script via `qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript
  <file> <unique-name>` + run it; `print()` lands in `journalctl --user`
  under kwin_wayland. Use a UNIQUE plugin name per probe (same name twice =
  loadScript -1). Properties: resourceClass/desktopFileName work, appId reads
  `undefined` even though docs advertise it.
- **llm-agents input**: do NOT add `follows = "nixpkgs"` — their binaries in `cache.numtide.com` are built against their own pinned nixpkgs; following yours = cache misses + rebuilds.
- `/etc/nixos/` is obsolete; the repo is the source of truth.

## Notes (closed threads)

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
