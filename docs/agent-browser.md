# Agent browser (`agent-browser`)

`agent-browser` (from nixpkgs; dashboard + skills embedded) drives a
**dedicated** CDP Chromium, never the normal browser. The point is
isolation: the CDP port can enumerate/control every tab in *that* instance —
your normal Firefox/LibreWolf/Chromium tabs are out of reach.

## Launch path

`agent-browser` is a wrapper (`scripts/agent-browser.sh`) that lazily starts
`agent-chrome` (`scripts/agent-chrome.sh`) on the first page command:
Chromium with

- `--user-data-dir=~/.local/share/agent-chrome`
- `--remote-debugging-port=9222` (bound to 127.0.0.1)
- `--no-startup-window`

then `agent-browser --cdp 9222`.

The two flags fix stray blank tabs: a normal Chromium launch starts with an
NTP tab and agent-browser opens a second one on attach, and `--auto-connect`
itself opens a blank tab — so each reopen used to leave `new tab +
about:blank`. With no startup window the first agent command creates the only
tab; the explicit `--cdp` port avoids auto-connect's extra tab.

A fresh launch also clears stale `*.target` bindings under
`$XDG_RUNTIME_DIR/agent-browser`. When Chromium is already running and the
session has no binding, the wrapper pre-creates that session's own tab
(`tab new`) so `open` cannot hijack the active tab.

No `--pin-tab`: the dedicated instance is the isolation boundary, and a
sticky pin reports `tab_gone` for every command after a Chromium restart.

Browser-less subcommands — `skills`, `session`, `dashboard`, `install`,
`upgrade`, `doctor`, `close`, `stream`, no args, `help`/`version` — and
explicit `--cdp`/`--auto-connect`/`connect` bypass the launch. `session` is
in that list so `session id`/`info` do not start Chromium at all.

## Streaming disabled

Each session daemon otherwise opens a random loopback WebSocket stream port
for the observability dashboard. The dashboard is unused and those leftover
ports were pure spam, so agent-chrome runs

```
agent-browser --session <sess> stream disable
```

after every page command (cheap, idempotent; covers daemons that restarted).
A port can exist while a command runs, never after it. `dashboard start`
still exists, but nothing starts it automatically.

## `ab`

`ab` (`shell/agents.sh`) is the agent-browser session: project-mode opencode
in `~/ab_workspace`, on the host network (`box -n`) so it can attach to this
Chromium. It exports `AGENT_BROWSER_CDP=9222`; agent-chrome honors that and
attaches instead of launching a second browser (and still disables the
stream).

Remaining `ab` args are joined into one `--prompt`; no args opens the TUI
without one.

## Do not run `agent-browser install`

That fetches an unpatched Chrome for Testing. The nixpkgs version updates
with `nyx -u`.

## opencode skill copy

`home/opencode.nix` copies the CLI's version-matched `core` skill into
`~/.config/opencode/skills/agent-browser-core` on every activation.

- Real files, not store symlinks: `scripts/nix-copy-tree.sh` records
  installed paths in `~/.nix_update_paths` and removes stale ones first.
- Only `core` is copied. Its `SKILL.md` lists the specialized skills, which
  stay runtime-only (`agent-browser skills get <name>`).

## Sandbox interaction

`ab` uses `box -n` because the default project-mode box has an egress-only
network namespace that cannot reach host loopback (CDP 9222). See
[sandbox](sandbox.md).
