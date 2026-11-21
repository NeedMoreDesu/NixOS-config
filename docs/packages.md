# Packages and programs

`modules/packages.nix` installs the system package set and wires the few
program modules whose setup matters.

## Program modules

- `programs.firefox.enable`.
- `programs.steam.enable` — not just the package: this sets up the FHS
  sandbox, `hardware.steam-hardware`, 32-bit PipeWire/Pulse audio and the
  Gamescope session.
  - `nixpkgs.config.allowUnfreePredicate` is scoped to names starting with
    `steam` (matches `steam`, `steam-run`, `steam-friends`,
    `steam-runtime`, ...), so nothing else silently turns unfree on.

## System packages

| Package | Purpose |
| --- | --- |
| `git` | Flake updates/rebuilds. |
| `fastfetch` | System info. |
| `sourcegit` | Git GUI (dock pin). |
| `godot`, `krita` | Creative tools. |
| `keepassxc` | Password manager. |
| `librewolf` | Secondary browser (dock pin). |
| `firefox` | Primary browser (module). |
| `chromium` | The CDP target for agent-browser, **not** a daily browser. |
| `agent-browser` + `agent-chrome` | Wrappers built with `replaceVars`. See [agent browser](agent-browser.md). |
| `bubblewrap`, `passt` | `box` sandbox. See [sandbox](sandbox.md). |
| `kdePackages.partitionmanager` | View the 1G EFI + rest ext4 layout graphically. nixpkgs-only, no flake input. |
| `zmx` | Session attach/detach (tmux-lite, Zig). Served at the held version while listed in `scripts/held-packages.nix`. See [pins](pins.md). |
| `seance` | From the seance flake input, not nixpkgs. See [seance](seance.md). |

`pkgs.system` is deprecated; `modules/packages.nix` derives
`hostSystem = pkgs.stdenv.hostPlatform.system` (flake outputs are still keyed
by the plain system string). See [rebuild](rebuild.md#nix-evaluation-gotcha-pkgssystem).

## LLM CLIs (`modules/llm-agents.nix`)

Adds the numtide binary cache (substituter) and installs `opencode` and
DeepSeek's `dsh` from `llm-agents.nix`.

The input deliberately does **not** follow our nixpkgs: its binaries in
`cache.numtide.com` are built against its own pinned nixpkgs. Following ours
would cause cache misses and rebuilds. See [pins](pins.md#input-policy).

## Other modules worth noting

- `modules/syncthing.nix` — Syncthing for `mika` (`dataDir = /home/mika`,
  `configDir = ~/.config/syncthing`, default ports open).
- `modules/printing.nix` — CUPS.
- `modules/audio.nix` — PipeWire (pulse compat), rtkit.
- `modules/users.nix` — `mika` in wheel + NetworkManager, with kate/emacs.
