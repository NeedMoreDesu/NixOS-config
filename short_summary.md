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
  desktop.nix          Plasma 6, SDDM (HiDPI on), xkb gb/mac, caps->ctrl
  mac-keys.nix         keyd: Cmd(⌘) acts as Ctrl for app shortcuts; Cmd+Tab,
                       Cmd+Space (launcher), Cmd+` (app windows); macOS-style
                       muscle memory on the Magic Keyboard without touching
                       physical Ctrl (terminal ^C/^R etc. unaffected)
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
- **Bluetooth peripherals dead at boot**: BlueZ doesn't page paired devices after adapter start. `bluetooth-reconnect` service pages *every* paired device (retries ~30 rounds; single shot races with adapter power-on and misses) until all show `Connected: yes`. Devices themselves are fine — they accept paging while asleep. Caveat: in-range headphones get pulled in too.
- **llm-agents input**: do NOT add `follows = "nixpkgs"` — their binaries in `cache.numtide.com` are built against their own pinned nixpkgs; following yours = cache misses + rebuilds.
- `/etc/nixos/` is obsolete; the repo is the source of truth.

## Next steps (not done yet)

- Rollback/GC: weekly nix-gc timer prunes profile generations >14d; boot menu capped at 20 entries. No `system.copySystemConfiguration` needed with a git repo
- No home.file/packages in HM yet — Plasma scaling + panel declared
