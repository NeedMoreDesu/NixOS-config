# short_summary.md

Entry point for this machine's NixOS config. Detailed manual lives in
[`docs/`](docs/). Repo: `~/nixos_config` (git-tracked; the flake only sees
committed/staged files, so `git add` before rebuilding after adding new
files).

Mode of operations for AI assistants: commit incrementally — each finished
change gets its own commit right away, don't batch up edits and don't wait to
be asked.

## What this system is

NixOS unstable (`nixpkgs#nixos-unstable`), one configured host `nixos` (the
flake is multi-host-ready: `nixosConfigurations.<name>` via `mkHost`).

KDE Plasma 6 + SDDM (Wayland), PipeWire, CUPS, NetworkManager, Bluetooth.
User `mika`; AI CLIs (`opencode`, DeepSeek `dsh`) from numtide's
`llm-agents.nix`. Emacs config is its own repo: a Prelude fork in
`~/.emacs.d` (GitHub, auto-cloned by `home/emacs.nix` on first activation).

## Rebuild

```
nyx
```

`nyx` → `rebuild.sh` → `nixos-rebuild switch` plus the xremap restart.
Flags: `-u` update, `-l` logout, `-r` reboot, `-k` re-apply Plasma to the
live session. See [rebuild](docs/rebuild.md) and
[update pins](docs/pins.md).

## Docs

| Doc | Subject |
| --- | --- |
| [rebuild](docs/rebuild.md) | `nyx`/`rebuild.sh`, flags, generations, GC, Nix eval gotchas. |
| [pins](docs/pins.md) | Flake updates, per-package holds, rollback, input policy. |
| [hosts](docs/hosts.md) | Hosts vs shared config; adding a host. |
| [layout](docs/layout.md) | File-by-file repository map. |
| [keyboard](docs/keyboard.md) | XKB, keyd, xremap, KWin shortcuts, all input debugging. |
| [plasma](docs/plasma.md) | Panel, top bar, custom plasmoids, kscreen, KWin remax. |
| [seance](docs/seance.md) | Terminal multiplexer config and keybinds. |
| [agent browser](docs/agent-browser.md) | Dedicated CDP Chromium, `ab`, skill copy. |
| [sandbox](docs/sandbox.md) | `box` project/system modes, pasta network, secrets. |
| [packages](docs/packages.md) | System packages, Steam, LLM CLIs, Syncthing. |
| [embeddings](docs/embeddings.md) | llama.cpp ROCm embedding server (EmbeddingGemma 2 Q8), omni input; activation pending; vLLM/SGLang for video later. |
| [inkling](docs/inkling.md) | Local Inkling 2 Mini (26B MoE Q4, vision 256k, CPU projector, Unsloth source build with bounded HIP pool cache), manual `ai` toggle, opencode provider; no autostart. |
| [lfm-vl](docs/lfm-vl.md) | Local LFM2.5-VL-1.6B Q4_K_M vision-language sidecar on 8090, 5k context, `ai on lfm`; no autostart. |

`docs/history/` holds setups that are no longer present:
[Bluetooth paging](docs/history/bluetooth-reconnect.md),
[Toshy](docs/history/toshy.md), [pasteboard](docs/history/pasteboard.md).

## Plans

`plans/` is transient implementation state, not documentation: one `.md` per
unfinished change (problem/evidence, chosen design, exact files, checklist).
When a plan lands, move the durable behavior and current state into the matching
`docs/` page and delete the plan file. Don't link plans as long-term docs.
No plan is currently open.

## Ground rules

- Git repo is the source of truth; `/etc/nixos/` is obsolete.
- XKB options are NixOS-managed (`modules/desktop.nix`) — don't use the
  Keyboard KCM. See [keyboard](docs/keyboard.md#kde-keyboard-kcm-hijacks-xkb-options-2026-11-08).
- Don't run `agent-browser install`. See [agent browser](docs/agent-browser.md#do-not-run-agent-browser-install).
- Local AI services (`llama-inkling`, `llama-embed`, `llama-vl`) have **no
  autostart**; start them by name with `ai on -l` / `ai on lfm`, stop with
  `ai off`. See [inkling](docs/inkling.md).
- `stateVersion` is pinned in `hosts/nixos/default.nix` — never bump it.
