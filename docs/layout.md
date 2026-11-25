# Repository layout

This is the map. Detailed behaviour lives in the linked subject docs.

## Top level

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs and `mkHost` / `nixosConfigurations.<name>`. See [pins](pins.md) and [hosts](hosts.md). |
| `rebuild.sh` | Flake rebuild one-liner. See [rebuild](rebuild.md). |
| `patches/` | Local package patches. `keyd-release-on-remove.patch` releases held keys on device removal; `llama-cuda-pool-cap.patch` bounds the HIP buffer-pool cache. See [keyboard](keyboard.md) and [inkling](inkling.md). |
| `docs/` | This manual. `docs/history/` holds closed/removed setups. |

## `shell/`

| Path | Purpose |
| --- | --- |
| `box.sh` | `bwrap` sandbox launcher + allowlists (shared). See [sandbox](sandbox.md). |
| `nyx.sh` | `nyx()` → `rebuild.sh --host $NYX_HOST`, `kde-restart()`. See [rebuild](rebuild.md). |
| `agents.sh` | `nyvibe`, `oc` + `ab`. See [agent browser](agent-browser.md) and [sandbox](sandbox.md). |
| `aliases.sh` | Host-independent aliases (`ai`, `caffeinate`). |

## `scripts/`

| Path | Purpose |
| --- | --- |
| `flake-update.sh` | `nyx -u` updater. See [pins](pins.md). |
| `flake-rollback.sh` | Interactive input rollback + per-package holds. See [pins](pins.md). |
| `held-packages.nix` | THE package-hold list. See [pins](pins.md). |
| `held-packages-lib.sh` | Shared hold helpers. |
| `flake-version.nix` | Best-effort version probe for one input/ref. |
| `flake-lock-info.nix` | Shared root-input TSV (name/rev/date/flake-ref). |
| `nix-copy-tree.sh` | Copy-with-manifest helper for activation-time file copies. |
| `screenshot.sh` | macOS-style screenshot bindings. See [keyboard](keyboard.md). |
| `agent-chrome.sh` | Dedicated CDP Chromium launcher. See [agent browser](agent-browser.md). |
| `agent-browser.sh` | Lazy front door for page commands. See [agent browser](agent-browser.md). |
| `kde_restart.sh` | Re-apply Plasma config to the live session (`kde-restart`). See [rebuild](rebuild.md). |

## `pkgs/`

| Path | Purpose |
| --- | --- |
| `box-tty-watch.c` / `.nix` | In-box TTY resize watcher. See [sandbox](sandbox.md). |
| `llama-cpp-unsloth.nix` | Unsloth llama.cpp prebuilt for Inkling (rollback fallback). See [inkling](inkling.md). |
| `llama-cpp-unsloth-src.nix` | Deployed source build of the prebuilt's exact commit and TheRock toolchain, plus the HIP pool-cap patch. See [inkling](inkling.md). |

## `hosts/`

| Path | Purpose |
| --- | --- |
| `hosts/<name>/default.nix` | Composition root. See [hosts](hosts.md). |
| `hosts/<name>/hardware-configuration.nix` | Generated at install. |
| `hosts/<name>/bashrc.sh` | Per-host shell shim. |
| `hosts/nixos/kscreen.nix` | Per-host 200% scaling user unit. See [plasma](plasma.md). |

## `home/` (shared home-manager)

One logical unit per file; `home/default.nix` holds the `mika` identity and
imports the rest.

| Path | Purpose |
| --- | --- |
| `home/plasma.nix` | Plasma panel, top bar, shortcuts. See [plasma](plasma.md) and [keyboard](keyboard.md). |
| `home/seance.nix` | `~/.config/seance/config.toml` → `assets/seance/config.toml`. See [seance](seance.md). |
| `home/opencode.nix` | opencode config + agent-browser skill copy. See [agent browser](agent-browser.md). |
| `home/emacs.nix` | Clones `~/.emacs.d` from the GitHub Prelude fork on first activation. |
| `home/kwin-remax.nix` | Login sweep user unit → `assets/kwin-remax/remax.js`. See [plasma](plasma.md). |
| `home/lock-layout.nix` | Forces the English XKB layout when the session locks. See [keyboard](keyboard.md#lock-screen-english-layout-homelock-layoutnix). |

Emacs config itself is a separate repo: a Prelude fork in `~/.emacs.d`
(auto-cloned by `home/emacs.nix`). Emacs-side keyboard work happens there,
not here.

## `assets/`

Copied payloads, one directory per consuming unit.

| Path | Purpose |
| --- | --- |
| `assets/seance/config.toml` | Seance keybinds and settings. See [seance](seance.md). |
| `assets/opencode/opencode.jsonc` | opencode permissions. See [sandbox](sandbox.md). |
| `assets/kwin-remax/remax.js` | Login maximize sweep. See [plasma](plasma.md). |
| `assets/plasma/ksysguard/sensorfaces/org.kde.mika.mutedtextonly` | Custom top-bar sensor face. See [plasma](plasma.md). |
| `assets/plasma/plasmoids/org.kde.mika.btbattery/` | Custom Bluetooth battery applet. See [plasma](plasma.md). |
| `assets/desktop/gb-mac-grave` | XKB symbols. See [keyboard](keyboard.md). |
| `assets/xremap/xremap.yml` | Keyboard policy. See [keyboard](keyboard.md). |
| `assets/mac-keys/keyd.conf` | keyd policy. See [keyboard](keyboard.md). |

## `modules/` (one topic per file)

| Path | Purpose |
| --- | --- |
| `boot.nix` | systemd-boot + EFI, `configurationLimit 20`. |
| `networking.nix` | NetworkManager; `tun` module for pasta. Hostname lives in the host. |
| `locale.nix` | Europe/Dublin, `en_IE`, console keymap `ie`. |
| `desktop.nix` | Plasma 6 + SDDM, XKB layouts. See [keyboard](keyboard.md). |
| `mac-keys.nix` | keyd sidecar + `hid_apple.fnmode=2`. See [keyboard](keyboard.md). |
| `xremap.nix` | xremap user service. See [keyboard](keyboard.md). |
| `audio.nix` | PipeWire (pulse compat), rtkit. |
| `bluetooth.nix` | Bluetooth stack only (`enable` + `powerOnBoot`); no autoload service. See [history](history/bluetooth-reconnect.md). |
| `printing.nix` | CUPS. |
| `syncthing.nix` | Syncthing for `mika`. See [packages](packages.md). |
| `users.nix` | `mika`: wheel + NetworkManager, kate/emacs. |
| `packages.nix` | System packages. See [packages](packages.md). |
| `held-packages.nix` | Per-package hold overlay. See [pins](pins.md). |
| `nix.nix` | nix-command + flakes; weekly GC and store optimise timers. See [rebuild](rebuild.md). |
| `llm-agents.nix` | numtide cache + opencode + dsh. See [packages](packages.md). |
| `home-manager.nix` | HM wiring (`useGlobalPkgs`, `users.mika` → `../home`). |
